Arguments and return values
===========================

This section discusses several core aspects pertaining to the implementation of internal functions. In particular we'll
take a look at how internal functions retrieve arguments and return values.

Function handler parameters
---------------------------

In the previous section you've already learned that the ``PHP_FUNCTION()`` macro resolves into a function declaration
of the following type::

    /* PHP_FUNCTION(func_name) */
    void zif_func_name(INTERNAL_FUNCTION_PARAMETERS) {
        /* implementation */
    }

Here ``INTERNAL_FUNCTION_PARAMETERS`` is another macro, which defines the parameters that the handler for an internal
function accepts. Lets substitute this macros as well::

    void zif_func_name(
        int ht, zval *return_value, zval **return_value_ptr,
        zval *this_ptr, int return_value_used TSRMLS_DC
    ) {
        /* implementation */
    }

We'll only touch on the meaning of the different parameters here and discuss the details of their usage in the remainder
of this section:

The first handler parameter ``ht`` is the number of arguments that have been passed during the function call. The weird
name of this parameter derives from the fact that a hashtable was passed in its place in earlier versions of PHP. When
implementing functions you should watch out and avoid naming any of your variables ``ht`` (which is the usual name for a
hashtable variable), otherwise you'll end up shadowing this parameter.

The ``return_value`` is a zval pointer used to specify the function's return value. It is initialized to ``IS_NULL`` by
default. You can modify it like any other zval using the ``ZVAL_*`` macros, however there are a number of extra macros
to simplify modifications of the ``return_value``, which will be discussed in the following.

``return_value_ptr`` is a ``zval **``, which allows you to return a completely different zval instead of modifying
``return_value``. This is necessary for by-reference returns, but can also be used to avoid unnecessary copies.

For methods ``this_ptr`` holds the ``$this`` value. The use of this value is discussed more closely in the
:doc:`/classes_objects` chapter.

Lastly, the ``return_value_used`` boolean specifies whether the calling code makes use of the return value, if such
information is available. For functions that both perform some operation on the input and return a complex output, this
information can be used to avoid computing the return value if it's not going to be used anyway.

Setting the ``return_value``
----------------------------

The ``return_value`` zval is allocated and initialized before the function handler is called. It is guaranteed to have
refcount=1, is_ref=0 and an ``IS_NULL`` type. Because we know that nobody else is making use of this zval, we can
directly modify it without bothering about copy-on-write separations. A few simple examples::

    PHP_FUNCTION(return_null) {
        /* don't need to do anything, it's already null! */
    }

    PHP_FUNCTION(return_true) {
        ZVAL_TRUE(return_value);
    }

    PHP_FUNCTION(return_pi) {
        ZVAL_DOUBLE(return_value, 3.141); /* approximate */
    }

    PHP_FUNCTION(return_hello_world) {
        ZVAL_STRING(return_value, "Hello world!", 1);
        /* Reminder: 1 means the strings needs to be duplicated */
    }

As setting the return value is such a common operation, there is a set of ``RETVAL_*`` macros, which are just
specializations of ``ZVAL_*`` on the ``return_value`` variable. The previous examples rewritten to make use of these
macros::

    PHP_FUNCTION(return_null) {
        /* already null */
    }

    PHP_FUNCTION(return_true) {
        RETVAL_TRUE;
    }

    PHP_FUNCTION(return_pi) {
        RETVAL_DOUBLE(3.141); /* approximate */
    }

    PHP_FUNCTION(return_hello_world) {
        RETVAL_STRING("Hello world!", 1);
    }

A ``RETVAL_*`` macro is available for all the ``ZVAL_*`` variants, here's a full list::

    RETVAL_NULL();
    RETVAL_BOOL(bval);
    RETVAL_FALSE;
    RETVAL_TRUE;
    RETVAL_LONG(lval);
    RETVAL_DOUBLE(dval);
    RETVAL_EMPTY_STRING();
    RETVAL_STRING(strval, duplicate);
    RETVAL_STRINGL(strval, strlen, duplicate);
    RETVAL_RESOURCE(resval);
    RETVAL_ZVAL(zval, copy, dtor);

Take care with the ``RETVAL_FALSE`` and ``RETVAL_TRUE`` macros: Unlike all the rest, these two are written without
parentheses.

The ``RETVAL_*`` macros only set the return value, but they don't return from the handler function. Consider the common
case, where you need to perform a number of error checks before going into the main body of a function::

    if (invalid_input()) {
        throw_warning();
        RETVAL_FALSE;
    }

    do_stuff();

This code won't work as intended, because ``RETVAL_FALSE`` will only set the return value to ``bool(false)``, but the
rest of the function will still continue to be executed. To avoid this, an explicit ``return`` from the handler is
required::

    if (invalid_input()) {
        throw_warning();
        RETVAL_FALSE;
        return;
    }

    do_stuff();

As this is once again a very common operation, there is another set of ``RETURN_*`` macros, which combine the
corresponding ``RETVAL_*`` with ``return``::

    if (invalid_input()) {
        throw_warning();
        RETURN_FALSE;
    }

    do_stuff();

There is one ``RETURN_*`` macro for every ``RETVAL_*`` macro, with the same signature. In practice, you will use
``RETURN_*`` most of the time and only switch to ``RETVAL_*`` in special cases like having common cleanup code which is
independent of the returned value.

The ``zend_parse_parameters()`` API
-----------------------------------

The most commonly used way to obtain the arguments (parameters) passed to an internal function is the
``zend_parse_parameters()`` API. This function handles everything from type checks, over optional arguments and
zval separation to variadic arguments. There are a number of other functions for getting function arguments, which we'll
take a look at lateron, but this is the method that nearly all internal functions utilize.

Here's a usage sample for the ``strcmp`` function::

    ZEND_FUNCTION(strcmp) {
        char *s1, *s2;
        int s1_len, s2_len;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC,
                "ss", &s1, &s1_len, &s2, &s2_len) == FAILURE
        ) {
            return;
        }

        RETURN_LONG(zend_binary_strcmp(s1, s1_len, s2, s2_len));
    }

The ``zend_parse_parameters()`` function first takes the number of arguments that were passed to the function. This
information is provided by the ``ZEND_NUM_ARGS()`` macro, which is really just a nicer name for the ``ht`` handler
parameter.

After that follows ``TSRMLS_CC`` (the thread-safety magic) and a parameter specification string, in this case ``"ss""``,
which means that the function accepts exactly two string parameters. After the specification a number of type specific
arguments is passed. To the most part these are target variables, into which the parameter's value will be written.
These are passed using an additional level of indirection (the ``&`` operator takes the address of the variables), so
that ``zend_parse_parameters()`` can modify their values.

The return value of zpp (we'll be using this shorthand in the following) has to be checked against ``FAILURE``, which is
returned when either a wrong number of arguments has been passed or they weren't of the correct type. By convention
functions must return ``null`` when a zpp failure occurs. As ``return_value`` is already null at this point, this
behavior can be implemented simply by adding a ``return``. Note that the convention to return null here is followed
rather strictly (unlike most other conventions in the PHP source code) and you should use it even if you have other
error return types like ``bool(false)`` as well.

The parameter specification is a string of type characters, with a number of additional modifiers. The types are loose,
e.g. you will be able to pass ``42`` to a string parameter (which can the be used as the string ``"42"``). However, the
type checks are stricter than PHP's normal casting operators, e.g. you will not be able to pass an array to a string
parameter.

The available type characters, the additional arguments that need to passed when they're used and the exact semantics
of what the type accepts are listed in the following table:

.. list-table::
    :header-rows: 1
    :widths: 3 8 20

    * - Type char
      - Variables
      - Semantics
    * - ``l``
      - ``long *lval``
      - Accepts null, bool, long and double according to ``convert_to_long()`` semantics. Accepts strings according to
        ``is_numeric_string()`` semantics with ``allow_errors = -1``. This means that ``"42"`` is accepted,
        ``"42foo"`` is also accepted but will throw a notice, whereas ``"foo"`` is rejected altogether.
    * - ``L``
      - ``long *lval``
      - Same as ``l`` but with different handling for doubles (and doubles in strings): If the double is outside the
        range supported by the ``long`` type, the value will be clipped at ``LONG_MIN`` / ``LONG_MAX``. The default
        behavior of the integer cast is to use wraparound instead. This means that if you pass ``PHP_INT_MAX + 1`` to an
        ``l`` argument, you'll get ``LONG_MIN`` (the MIN is not a typo) as the result.
    * - ``d``
      - ``double *dval``
      - Accepts null, bool, long and double according to ``convert_to_double()`` semantics and strings according to
        ``is_numeric_string()`` with ``allow_errors = -1``.
    * - ``s``
      - ``char **strval, int *strlen``
      - Accepts null, bool, long, double and string according to ``convert_to_string()`` semantics. Accepts objects if
        they have a ``__toString()`` method (or the internal equivalent).
    * - ``p``
      - ``char **strval, int *strlen``
      - Accepts a "valid path". It behaves the same as ``s``, but rejects strings that contain NUL bytes. This is
        necessary because file handling functions usually aren't binary-safe and passing them strings with NUL bytes
        can easily lead to security vulnerabilities.
    * - ``b``
      - ``zend_bool *bval``
      - Accepts null, bool, long, double and string according to ``convert_to_boolean()`` semantics.
    * - ``r``
      - ``zval **zv``
      - Accepts only resources.
    * - ``a``
      - ``zval **zv``
      - Accepts only arrays.
    * - ``A``
      - ``zval **zv``
      - Accepts only arrays and objects.
    * - ``h``
      - ``HashTable **ht``
      - Accepts only arrays. As such this is the same as ``a``, but it directly provides you with the underlying
        hashtable of the array. With the ``a`` type you often need to use ``Z_ARRVAL_P()`` afterwards.
    * - ``H``
      - ``HashTable **ht``
      - Accepts only arrays and objects and once again provides you with a hashtable. For objects this will be the
        properties hashtable.
    * - ``o``
      - ``zval **zv``
      - Accepts only objects.
    * - ``O``
      - ``zval **zv, zend_class_entry *ce``
      - Accepts only objects of type ``ce`` (according to ``instanceof`` semantics). Unlike all the previous cases,
        ``ce`` is not a target argument here. Rather it provides additional information for the type check. The target
        argument is the ``zv``.
    * - ``C``
      - ``zend_class_entry **ce``
      - Accepts a valid class name. The passed argument will be converted to string, followed by a class entry lookup.
        ``ce`` here doubles as an input and an output argument. The found class entry is written into ``*ce``, but
        ``*ce`` can already contain a class entry beforehand: In this case the passed class must be ``*ce`` or a
        subclass thereof (once again using ``instanceof`` semantics).
    * - ``f``
      - ``zend_fcall_info *fci, zend_fcall_info_cache *fcc``
      - Accepts a valid callable. What ``fci`` and ``fcc`` are is outside the scope of this chapter.
    * - ``z``
      - ``zval **zv``
      - Accepts any value.
    * - ``Z``
      - ``zval ***zv``
      - Accepts any value. This provides the zval with another level of indirection, which is necessary if you want to
        perform operations like zval separation.

Lets take a look at a few more examples! Here's the zpp call for the ``array_pad()`` function::

    PHP_FUNCTION(array_pad) {
        zval *input;
        long pad_size;
        zval *pad_value;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC,
                "alz", &input, &pad_size, &pad_value) == FAILURE
        ) {
            return;
        }

        /* ... */
    }

The function accepts an array (``a``), an integer (``l``) and an arbitrary value (``z``). The array is fetched into the
``zval *input``, the integer into ``long pad_size`` and the value into ``zval *pad_value``. If you compare these types
with the previous table, you'll note that the variable declarations have one ``*`` less than the arguments listed in
the table. The additional level of indirection is added by the use of the ``&`` operator during the zpp call.

``iterator_count()`` is an example of a function using the ``O`` type::

    PHP_FUNCTION(iterator_count) {
        zval *obj;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC,
                "O", &obj, zend_ce_traversable) == FAILURE
        ) {
            RETURN_FALSE; /* <-- someone was naughty and used the wrong return type */
        }

        /* ... */
    }

The ``O`` type verifies that the passed argument is an instance of a certain class/interface. For this purpose you need
to pass the expected class entry as an additional argument after the target zval. Note that ``&`` is not being used
here: The class entry is just extra information for zpp, it will not be modified.

The ``C`` type uses a different approach to specify additional data. Here's a sample usage for
``ArrayObject::setIteratorClass()`` method::

    SPL_METHOD(Array, setIteratorClass) {
        zend_class_entry *ce_get_iterator = spl_ce_Iterator;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "C", &ce_get_iterator) == FAILURE) {
            return;
        }

        /* ... */
    }

The variable ``ce_get_iterator`` is initialized to ``spl_ce_Iterator`` and then passed (this time using ``&`` once
again) to zpp. This tells zpp that the argument must be a class name which corresponds to a subclass of Iterator (or is
the Iterator class itself). The ``ce_get_iterator`` variable will then be modified to contain the class entry for the
specified class.

In order to accept any valid class name (without any inheritance restrictions) you need to initialize the class entry
variable to ``NULL``::

    PHP_FUNCTION(takes_class_name) {
        zend_class_entry *ce = NULL;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "C", &ce) == FAILURE) {
            return;
        }

        /* ... */
    }

Optional arguments
------------------

All functions in the preceding examples accept a fixed number of required parameters: You can pass exactly three
arguments to ``array_pad()``, not more, not less. Anything else will result a zpp ``FAILURE`` (and a warning). However,
many functions need to handle a number of additional, optional arguments and of course the ``zend_parse_parameters()``
API has support for this as well.

Required and optional parameters are separated with a ``|`` in the parameter specification string::

    PHP_FUNCTION(str_pad) {
        char *input;
        int input_len;
        long pad_length;
        char *pad_str_val = " ";
        int pad_str_len = 1;
        long pad_type_val = STR_PAD_RIGHT;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "sl|sl",
                &input, &input_len, &pad_length, &pad_str_val, &pad_str_len, &pad_type_val) == FAILURE
        ) {
            return;
        }
    }

The first two arguments of the ``str_pad()`` function, namely the input string and pad length, must always be specified.
Optionally you can also specify the string with which to pad (``pad_str_val``) and the type of the padding
(``pad_type_val``).

If an optional argument is not specified, then zpp will not assign any value to the corresponding target variables. E.g.
if you only pass two arguments to ``str_pad()``, then ``pad_str_val``, ``pad_str_len`` and ``pad_type_val`` will not
be modified. As such target variables for optional arguments should always be initialized to some default value. In the
previous example that would be the ``" "`` padding string and ``STR_PAD_RIGHT`` padding type.

The default value doesn't have to be an actual default value, in the PHP sense of the word. For example it is common to
assign ``NULL`` to optional zval arguments (and other arguments with pointer types, like strings and hashtables)::

    PHP_FUNCTION(array_keys) {
        zval *input, *search_value = NULL;
        zend_bool strict = 0;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC,
                "a|zb", &input, &search_value, &strict) == FAILURE
        ) {
            return;
        }

        /* ... */
    }

Here ``search_value`` is initialized to ``NULL``. This value is only used as a way to determine whether or not this
argument was passed, by checking ``search_value != NULL`` in the implementation. The same can't be done with non-pointer
types (e.g. initializing ``long lval = 0``, you won't be able to distinguish between the parameter not being passed and
the value ``0`` being passed). We'll learn how to deal with soon, but first need to introduce another zpp feature:

Nullable arguments
------------------

From the previous section you're already familiar with the ``allow_null`` annotation for arguments, which allows passing
of ``null`` in addition to the hinted type. The same can be achieved with zpp by appending an exclamation mark (``!``)
after the type character.

For pointer types, i.e. ``z``, ``Z``, ``a``, ``A``, ``h``, ``H``, ``o``, ``O``, ``C``, ``r`` and ``s`` the value
``NULL`` will be assigned to the target variable if a ``null`` zval is passed to the argument. For ``s`` additionally
the string length is set to ``0``. For the ``f`` type ``fci->size`` and ``fcc->initialized`` will be set to ``0`` (you
don't need to know what those two are, for now). We'll discuss how the other types (like ``l``) work in a minute. First,
let's look at an example of this functionality::

    PHP_FUNCTION(array_column) {
        zval **zcolumn, **zkey = NULL;
        HashTable *arr_hash;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC,
                "hZ!|Z!", &arr_hash, &zcolumn, &zkey) == FAILURE
        ) {
            return;
        }

        /* ... */
    }



TODO:
 * Other parameter APIs
 * return_value_ptr
 * return_value_used
 * Error handling (?)
 * Passthru
 * zpp without ZEND_NUM_ARGS()
 * zpp with ! / etc