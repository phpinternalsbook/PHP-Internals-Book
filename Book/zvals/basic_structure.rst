Basic structure
===============

A zval (short for "Zend value") represents an arbitrary PHP value. As such it is likely the most important structure in
all of PHP and you'll be working with it a lot. This section describes the basic concepts behind zvals and their use.



Types and values
----------------

Among other things every zval stores some value and the type this value has. This is necessary because PHP is a dynamically
typed language and as such variable types are only known at run-time and not at compile-time. Furthermore the type can change
during the life of a zval, so if the zval previously stored an integer it may contain a string at a later point in time.

The type is stored as an integer tag (an unsigned char). It can be one of eight values, which correspond to the eight types
available in PHP. These values are referred to using constants of the form ``IS_TYPE``. E.g. ``IS_NULL`` corresponds to the
null type and ``IS_STRING`` corresponds to the string type.

The actual value is stored in a union, which is defined as follows::

    typedef union _zvalue_value {
        long lval;
        double dval;
        struct {
            char *val;
            int len;
        } str;
        HashTable *ht;
        zend_object_value obj;
    } zvalue_value;

To those not familiar with the concept of unions: A union defines multiple members of different types, but only one of
them can ever be used at a time. E.g. if the ``value.lval`` member was set, then you also need to look up the value using
``value.lval`` and not one of the other members (doing so would violate "strict aliasing" guarantees and lead to
undefined behaviour). The reason is that unions store all their members at the same memory location and just interpret the
value located there differently depending on which member you access. The size of the union is the size of its largest
member.

When working with zvals the type tag is used to find out which of the union's member is currently in use. Before having a
look at the APIs used to do so, let's walk through the different types PHP supports and how they are stored:

The simplest type is ``IS_NULL``: It doesn't need to actually store any value, because there is just one ``null`` value.

For storing numbers PHP provides the types ``IS_LONG`` and ``IS_DOUBLE``, which make use of the ``long lval`` and
``double dval`` members respectively. The former is used to store integers, whereas the latter stores floating point
numbers.

There are some things that one should be aware of about the ``long`` type: Firstly, this is a signed integer type, i.e.
it can store both positive and negative integers, but is commonly not well suited for doing bitwise operations. Secondly,
``long`` has different sizes on different platforms: On 32bit systems it is 32 bits / 4 bytes large, but on 64bit systems
it's size will be either 4 or 8 bytes. In particular 64bit Unix systems typically have 8 byte longs, whereas 64bit Windows
uses only 4 bytes.

For this reason you shouldn't rely on any particular size for the ``long`` type. The minimum and maximum values a ``long``
can store are available via ``LONG_MIN`` and ``LONG_MAX`` and the size of the type can be accessed using ``SIZEOF_LONG``
(unlike ``sizeof(long)`` this is also usable in ``#if`` directives).

The ``double`` type used to store floating point numbers is (typically) an 8-byte value following the IEEE754 specification.
The details of this format won't be discussed here, but you should at least be aware of the fact that this type has limited
precision and commonly doesn't store the exact value you want.

Booleans use the ``IS_BOOL`` flag and are stored in the ``long lval`` member as values 0 (for false) and 1 (for true). As there
are only these two values one could theoretically use some smaller type instead (like ``zend_bool``, which is an unsigned char),
but as the ``zvalue_value`` union has the size of its *largest* member this would not actually result in any memory savings.
As such the ``lval`` member is reused.

Strings (``IS_STRING``) are stored in ``struct { char *val; int len; } str``, i.e. they consist of a ``char*`` string and
an ``int`` length. PHP strings need to store an explicit length in order to allow use of NUL bytes (``'\0'``) in them (what is
actually called "binary safety").
Regardless of this, the strings used by PHP are still NUL-terminated to ease interoperability with library functions which
don't take length arguments and expect NUL-terminated strings instead. Of course in this case the strings won't be binary
safe anymore and will be cut off at the first NUL byte they contain. For example many filesystem related functions behave
like this as well as lots of libc string functions.

The length of a string is in bytes (not Unicode code points) and does **not** include the terminating NUL byte: The length
of the string ``"foo"`` is 3, even though it is actually stored using 4 bytes. If you determine the length of a constant string
using ``sizeof`` you need to make sure to subtract one: ``strlen("foo") == sizeof("foo") - 1``

Furthermore it's important to realize that the string length is stored in an ``int`` and not a ``long`` or some other type.
This is an unfortunate historical artifact, which limits the length of strings to 2147483647 bytes. Strings larger than this
would cause an overflow (thus making the length negative).

The remaining three types will only be mentioned here quickly and discussed in greater detail in their own chapters:

Arrays use the ``IS_ARRAY`` type tag and are stored in the ``HashTable *ht`` member. How the ``HashTable`` structure works
will be discussed in the :doc:`hashtable chapter </hashtables>`.

Objects (``IS_OBJECT``) use the ``zend_object_value obj`` member, which consists of an "object handle", which is an integer
ID used to look up the actual data of the object, and a set of "object handlers", which define how the object behaves.
PHP's class and object system will be described in the :doc:`object chapter </classes_objects>`.

Resources (``IS_RESOURCE``) are similar to objects in that they also store a unique ID that can be used to look up the
actual value. This ID is stored in the ``long lval`` member. Resources are covered in the [TODO:resources ref] chapter.

To summarize here's a table with all the available type tags and the corresponding storage location for their values:

.. list-table::
    :header-rows: 1

    * - Type tag
      - Storage location
    * - ``IS_NULL``
      - none
    * - ``IS_BOOL``
      - ``long lval``
    * - ``IS_LONG``
      - ``long lval``
    * - ``IS_DOUBLE``
      - ``double dval``
    * - ``IS_STRING``
      - ``struct { char *val; int len; } str``
    * - ``IS_ARRAY``
      - ``HashTable *ht``
    * - ``IS_OBJECT``
      - ``zend_object_value obj``
    * - ``IS_RESOURCE``
      - ``long lval``

Access macros
-------------

Lets now have a look at how the ``zval`` struct actually looks like::

    typedef struct _zval_struct {
        zvalue_value value;
        zend_uint refcount__gc;
        zend_uchar type;
        zend_uchar is_ref__gc;
    } zval;

As already mentioned the zval has members to store a ``value`` and its ``type``. The value is stored in the ``zvalue_value``
union discussed above and the type tag is held in a ``zend_uchar``. Additionally the structure has two properties ending in
``__gc``, which are used for the garbage collection mechanism PHP employs. We'll ignore them for now and discuss their
function in the next section.

Knowing the zval structure you can now write code making use of it::

    zval *zv_ptr = /* ... get zval from somewhere */;

    if (zv_ptr->type == IS_LONG) {
        php_printf("Zval is a long with value %ld\n", zv_ptr->value.lval);
    } else /* ... handle other types */

While the above code works, this is not the idiomatic way to write it. It directly accesses the zval members rather than
using a special set of access macros for this purpose::

    zval *zv_ptr = /* ... */;

    if (Z_TYPE_P(zv_ptr) == IS_LONG) {
        php_printf("Zval is a long with value %ld\n", Z_LVAL_P(zv_ptr));
    } else /* ... */

The above code uses the ``Z_TYPE_P()`` macro for retrieving the type tag and ``Z_LVAL_P()`` to get the long (integer)
value. All the access macros have variants with a ``_P`` suffix, a ``_PP`` suffix or no suffix at all. Which one you
use depends on whether you are working on a ``zval``, a ``zval*`` or a ``zval**``::

    zval zv;
    zval *zv_ptr;
    zval **zv_ptr_ptr;
    zval ***zv_ptr_ptr_ptr;

    Z_TYPE(zv);                 // = zv.type
    Z_TYPE_P(zv_ptr);           // = zv_ptr->type
    Z_TYPE_PP(zv_ptr_ptr);      // = (*zv_ptr_ptr)->type
    Z_TYPE_PP(*zv_ptr_ptr_ptr); // = (**zv_ptr_ptr_ptr)->type

Basically the number of ``P``\s should be the same as the number of ``*``\s of the type. This only works until
``zval**``, i.e. there are no special macros for working with ``zval***`` as this is rarely necessary in practice
(you'll just have to dereference the value first using the ``*`` operator).

Similarly to ``Z_LVAL`` there are also macros for fetching values of all the other types. To demonstrate their
usage we'll create a simple function for dumping a zval::

    PHP_FUNCTION(dump)
    {
        zval *zv_ptr;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "z", &zv_ptr) == FAILURE) {
            return;
        }

        switch (Z_TYPE_P(zv_ptr)) {
            case IS_NULL:
                php_printf("NULL: null\n");
                break;
            case IS_BOOL:
                if (Z_BVAL_P(zv_ptr)) {
                    php_printf("BOOL: true\n");
                } else {
                    php_printf("BOOL: false\n");
                }
                break;
            case IS_LONG:
                php_printf("LONG: %ld\n", Z_LVAL_P(zv_ptr));
                break;
            case IS_DOUBLE:
                php_printf("DOUBLE: %f\n", Z_DVAL_P(zv_ptr)); /* TODO %f? */
                break;
            case IS_STRING:
                php_printf("STRING: value=\"");
                PHPWRITE(Z_STRVAL_P(zv_ptr), Z_STRLEN_P(zv_ptr));
                php_printf("\", length=%d\n", Z_STRLEN_P(zv_ptr));
                break;
            case IS_RESOURCE:
                php_printf("RESOURCE: id=%ld\n", Z_RESVAL_P(zv_ptr));
                break;
            case IS_ARRAY:
                php_printf("ARRAY: hashtable=0x%lx\n", Z_ARRVAL_P(zv_ptr)); /* TODO %lx? */
                break;
            case IS_OBJECT:
                php_printg("OBJECT: ???");
                break;
        }
    }

    const zend_function_entry funcs[] = { /* TODO verify zfe */
        PHP_FE(dump, NULL)
        PHP_FE_END
    };

Lets try it out::

    dump(null);                 // NULL: null
    dump(true);                 // BOOL: true
    dump(false);                // BOOL: false
    dump(42);                   // LONG: 42
    dump(4.2);                  // DOUBLE: 4.2
    dump("foo");                // STRING: value="foo", length=3
    dump(fopen(__FILE__, "r")); // RESOURCE: id=???
    dump(array(1, 2, 3));       // ARRAY: hashtable=0x???
    dump(new stdClass);         // OBJECT: ???

The macros for accessing the values are pretty straightforward: ``Z_BVAL`` for bools, ``Z_LVAL`` for longs,
``Z_DVAL`` for doubles. For strings ``Z_STRVAL`` returns the actual ``char*`` string, whereas ``Z_STRLEN``
provides us with the length. The resource ID can be fetched using ``Z_RESVAL`` and the ``HashTable*`` of
an array is accessed with ``Z_ARRVAL``. How object values are accessed will not be covered here as it
requires some more background knowledge.

When you want to access the contents of a zval you should always go through these macros, rather than
directly accessing its members. This maintains a level of abstraction and makes the intention clearer:
For example, if you directly accessed the ``lval`` member you could either be fetching the bool value,
the long value or the resource ID. Using ``Z_BVAL``, ``Z_LVAL`` and ``Z_RESVAL`` instead makes the
intention unambiguous. You also protect yourself about possible future changes in the internal API.
The internal API has already changed though time, and macros have always been updated so that extension
code still works while the structures, for example, have had their alignement changed.

Setting the value
-----------------

Most of the macros introduced above just access some member of the zval structure and as such you can use them
both to read and to write the respective values. As an example consider the following function which simply
returns the string "hello world!"::

    PHP_FUNCTION(hello_world) {
        Z_TYPE_P(return_value) = IS_STRING;
        Z_STRVAL_P(return_value) = estrdup("hello world!");
        Z_STRLEN_P(return_value) = strlen("hello world!");
    };

    /* ... */
        PHP_FE(hello_world, NULL)
    /* ... */

Running ``php -r "echo hello_world();"`` should now print ``hello world!`` to the terminal.

In the above example we set the ``return_value`` variable, which is a ``zval*`` provided by the
``PHP_FUNCTION`` macro. We'll look at this variable in more detail in the next chapter, for now it should
suffice to know that the value of this variable will be the return value of the function. By default
it is initialized to have type ``IS_NULL``.

Setting a zval value using the access macros is really straightforward, but there are some things one should
keep in mind: First of all you need to remember that the type tag determines the type of a zval. It doesn't
suffice to just set the value (via ``Z_STRVAL`` and ``Z_STRLEN`` here), you always need to set the type tag, too.

Furthermore you need to be aware of the fact that in most cases the zval "owns" its value and that the zval
will have a longer life-time than the scope in which you set its value. Sometimes this doesn't apply when dealing
with temporary zvals, but in most cases it's true.

Using the above example this means that the ``return_value`` will live on after our function body leaves (which
is quite obvious, otherwise nobody could use the return value), so it can't make use of any temporary values
of the function. E.g. just writing ``Z_STRVAL_P(return_value) = "hello world!"`` would be invalid, because the
string literal ``"hello world!"`` ceases to exist after the body is left (this is true for every stack allocated
variables in C).

Because of this we need to copy the string using ``estrdup()``. This will create a separate copy of the string
on the heap. Because the zval "owns" its value it will make sure to free this copy when the zval is destroyed.
This also applies to any other "complex" value of the zval. E.g. if you set the ``HashTable*`` for an array
the zval will take ownership of it and free it when the zval is destroyed. When using primitive types like
integers or doubles you obviously don't need to care about this as they are always copied.

Lastly it should be pointed out that not all of the access macros directly access a member. The ``Z_BVAL``
macro for example is defined as follows::

    #define Z_BVAL(zval) ((zend_bool)(zval).value.lval)

Because this macro contains a cast you will not be able to write ``Z_BVAL_P(return_value) = 1``. Apart from
some of the object-related macros this is the only exception though. All the other access macros can be
used to set values.

In practice you won't have to worry about the last bit though: As setting the zval value is such a common
task PHP provides another set of macros for this purpose. They allow you to set the type tag and the
value at the same time. Rewriting the previous example using such a macro yields::

    PHP_FUNCTION(hello_world) {
        ZVAL_STRINGL(return_value, estrdup("hello world!"), strlen("hello world!"), 0);
    }

As it is very common that the string has to be copied when assigning to the zval, the last (boolean) parameter
of the ``ZVAL_STRINGL`` macro can handle this for you. If you pass ``0`` the string is used as is, but if you
pass ``1`` it will be copied using ``estrndup()``. Thus our example can be rewritten as::

    PHP_FUNCTION(hello_world) {
        ZVAL_STRINGL(return_value, "hello world!", strlen("hello world!"), 1);
    }

Furthermore we don't need to manually compute the ``strlen`` and can use the ``ZVAL_STRING`` macro (without the
``L`` at the end) instead::

    PHP_FUNCTION(hello_world) {
        ZVAL_STRING(return_value, "hello world!", 1);
    }

If you know the length of the string (because it was passed to you in some way) you should always make use of it
via the ``ZVAL_STRINGL`` macro in order to preserve binary-safety. If you don't know the length (or know that
the string doesn't contain NUL bytes, as is usually the case with literals) you can use ``ZVAL_STRING`` instead.

Apart from ``ZVAL_STRING(L)`` there are a few more macros for setting values, which are listed in the following
example::

    ZVAL_NULL(return_value);

    ZVAL_BOOL(return_value, 0);
    ZVAL_BOOL(return_value, 1);
    /* or better */
    ZVAL_FALSE(return_value);
    ZVAL_TRUE(return_value);

    ZVAL_LONG(return_value, 42);
    ZVAL_DOUBLE(return_value, 4.2);
    ZVAL_RESOURCE(return_value, resource_id);

    ZVAL_EMPTY_STRING(return_value);
    /* = ZVAL_STRING(return_value, "", 1); */

    ZVAL_STRING(return_value, "string", 1);
    /* = ZVAL_STRING(return_value, estrdup("string"), 0); */

    ZVAL_STRINGL(return_value, "nul\0string", 10, 1);
    /* = ZVAL_STRINGL(return_value, estrndup("nul\0string", 10), 10, 0); */

