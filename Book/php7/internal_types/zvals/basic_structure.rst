Basic structure
===============

A zval (short for "Zend value") represents an arbitrary PHP value. As such it is likely the most important structure in
all of PHP and you'll be working with it a lot. This section describes the basic concepts behind zvals and their use.

Types and values
----------------

Among other things, every zval stores some value and the type this value has. This is necessary because PHP is a
dynamically typed language and as such variable types are only known at run-time and not at compile-time. Furthermore
the type can change during the life of a zval, so if the zval previously stored an integer it may contain a string at a
later point in time.

The type is stored as an integer tag (an unsigned int). It can be one of several values. Some values correspond to the eight
types available in PHP, others are used for internal engine purpose only. These values are referred to using constants
of the form ``IS_TYPE``. E.g. ``IS_NULL`` corresponds to the null type and ``IS_STRING`` corresponds to the string type.

The actual value is stored in a union, which is defined as follows::

    typedef union _zend_value {
        zend_long         lval;
        double            dval;
        zend_refcounted  *counted;
        zend_string      *str;
        zend_array       *arr;
        zend_object      *obj;
        zend_resource    *res;
        zend_reference   *ref;
        zend_ast_ref     *ast;
        zval             *zv;
        void             *ptr;
        zend_class_entry *ce;
        zend_function    *func;
        struct {
            uint32_t w1;
            uint32_t w2;
        } ww;
    } zend_value;

To those not familiar with the concept of unions: A union defines multiple members of different types, but only one of
them can ever be used at a time. E.g. if the ``value.lval`` member was set, then you also need to look up the value
using ``value.lval`` and not one of the other members (doing so would violate "strict aliasing" guarantees and lead to
undefined behaviour). The reason is that unions store all their members at the same memory location and just interpret
the value located there differently depending on which member you access. The size of the union is the size of its
largest member.

When working with zvals the type tag is used to find out which of the union's member is currently in use. Before having
a look at the APIs used to do so, let's walk through the different types PHP supports and how they are stored:

The simplest type is ``IS_NULL``: It doesn't need to actually store any value, because there is just one ``null`` value.

For storing numbers PHP provides the types ``IS_LONG`` and ``IS_DOUBLE``, which make use of the ``zend_long lval`` and
``double dval`` members respectively. The former is used to store integers, whereas the latter stores floating point
numbers.

There are some things that one should be aware of about the ``zend_long`` type: Firstly, this is a signed integer type,
i.e. it can store both positive and negative integers, but is commonly not well suited for doing bitwise operations.
Secondly, ``zend_long`` represents an abstraction of the platform long, so whatever the platform you're using,
``zend_long`` weights 4 bytes on 32bit platforms and 8 bytes on 64bit ones.

In addition to that, you may use macros related to longs, ``SIZEOF_ZEND_LONG`` or ``ZEND_LONG_MAX`` f.e.
See
`Zend/zend_long.h <https://github.com/php/php-src/blob/c3b910370c5c92007c3e3579024490345cb7f9a7/Zend/zend_long.h>`_
in source code for more information.

The ``double`` type used to store floating point numbers is (typically) an 8-byte value following the IEEE-754
specification. The details of this format won't be discussed here, but you should at least be aware of the fact that
this type has limited precision and commonly doesn't store the exact value you want.

Booleans use either the ``IS_TRUE`` or ``IS_FALSE`` flag and don't need to store any more info. There exists what's
called a "fake type" flagged as ``_IS_BOOL``, but you shouldn't make use of it as a zval type, this is incorrect. This
fake type is used in some rare uncommon internal situations (like type hints f.e).

The remaining four types will only be mentioned here quickly and discussed in greater detail in their own chapters:

Strings (``IS_STRING``) are stored in a ``zend_string`` structure, i.e. they consist of a ``char *`` string
and an ``size_t`` length. You will find more information about the ``zend_string`` structure and its dedicated API
into the :doc:`string <../strings>` chapter.

Arrays use the ``IS_ARRAY`` type tag and are stored in the ``zend_array *arr`` member. How the ``HashTable`` structure
works will be discussed in the :doc:`Hashtables <../hashtables>` chapter.

Objects (``IS_OBJECT``) use the ``zend_object *obj`` member. PHP's class and object system will be described in the
:doc:`objects <../objects>` chapter.

Resources (``IS_RESOURCE``) are a special type using the ``zend_resource *res`` member. Resources are covered in the
:doc:`Resources <../zend_resources>` chapter.

.. todo:: Update ref once resources chapter is written.

To summarize, here's a table with all the available type tags and the corresponding storage location for their values:

.. list-table::
    :header-rows: 1

    * - Type tag
      - Storage location
    * - ``IS_NULL``
      - none
    * - ``IS_TRUE`` or ``IS_FALSE``
      - none
    * - ``IS_LONG``
      - ``zend_long lval``
    * - ``IS_DOUBLE``
      - ``double dval``
    * - ``IS_STRING``
      - ``zend_string *str``
    * - ``IS_ARRAY``
      - ``zend_array *arr``
    * - ``IS_OBJECT``
      - ``zend_object *obj``
    * - ``IS_RESOURCE``
      - ``zend_resource *res``

Special types
,,,,,,,,,,,,,

You may see other types carried into the zvals, which we did not review yet.
Those types are special types that do not exist as-is in the PHP language userland, but are used into the engine for
internal use-case only. The zval structure has been thought to be very flexible, and is used internally to carry
virtually any type of data of interest, and not only the PHP specific types we just reviewed above.

The special ``IS_UNDEF`` type has a special meaning. That means "This zval contains no data of interest, do not access
any data field from it". This is used for :doc:`memory management <memory_and_gc>` purposes. If you see an ``IS_UNDEF``
zval, that means that it is of no special type and contains no valid information.

The ``zend_refcounted *counted`` field is very tricky to understand. Basically, that field serve as a header for any
other reference-countable type. This part is detailed into the :doc:`memory_and_gc` chapter.

The ``zend_reference *ref`` is used to represent a PHP reference. The ``IS_REFERENCE`` type flag is then used.
Here as well, we dedicated a chapter to such a concept, have a look at the :doc:`memory_and_gc` chapter.

The ``zend_ast_ref *ast`` is used when you manipulate the AST from the compiler. The PHP compilation is detailed into
the :doc:`../../zend_engine/zend_compiler` chapter.

The ``zval *zv`` is used internally only. You should not have to manipulate it. This works together with the
``IS_INDIRECT,`` and that allows one to embed a ``zval *`` into a ``zval``. Very specific dark usage of such a field is used
f.e to represent ``$GLOBALS[]`` PHP superglobal.

Something very useful is the ``void *ptr`` field. Same here : no PHP userland usage but internal only.
You will basically use this field when you want to store "something" into a zval. Yep, that's a ``void *``, which in C
represents "a pointer to some memory area of any size, containing (hopefully) anything".
The ``IS_PTR`` flag type is then used in the zval.

When you'll read the :doc:`objects <../objects>` chapter, you'll learn about ``zend_class_entry`` type. The zval
``zend_class_entry *ce`` field is used to carry a reference to a PHP class into a zval. Here again, there is no direct
usage of such a situation into the PHP language itself (userland), but internally you'll need that.

Finally, the ``zend_function *func`` field is used to embed a PHP function into a zval. The 
:doc:`functions <../functions>` chapter details PHP functions.

Access macros
-------------

Lets now have a look at how the ``zval`` struct actually looks like::

    struct _zval_struct {
	    zend_value        value;			/* value */
	    union {
		    struct {
			    ZEND_ENDIAN_LOHI_4(
				    zend_uchar    type,			/* active type */
				    zend_uchar    type_flags,
				    zend_uchar    const_flags,
				    zend_uchar    reserved)	    /* call info for EX(This) */
		    } v;
		    uint32_t type_info;
	    } u1;
	    union {
		    uint32_t     next;                 /* hash collision chain */
		    uint32_t     cache_slot;           /* literal cache slot */
		    uint32_t     lineno;               /* line number (for ast nodes) */
		    uint32_t     num_args;             /* arguments number for EX(This) */
		    uint32_t     fe_pos;               /* foreach position */
		    uint32_t     fe_iter_idx;          /* foreach iterator index */
		    uint32_t     access_flags;         /* class constant access flags */
		    uint32_t     property_guard;       /* single property guard */
		    uint32_t     extra;                /* not further specified */
	    } u2;
    };

As already mentioned, the zval has members to store a ``value`` and its ``type_info``. The value is stored in the
``zvalue_value`` union discussed above and the type tag is held in a ``zend_uchar`` itself part of the ``u1`` union.
Additionally the structure has a ``u2`` property. We'll ignore them for now and discuss their function later.

``u1`` is accessed using ``type_info``. ``type_info`` is shrunk into detailed ``type``, ``type_flags``,
``const_flags`` and ``reserved`` fields. Remember, we are in a union for ``u1`` here. So the four information in the
``u1.v`` field weighs the same as the information stored into the ``u1.type_info``. A clever memory alignment rule
has been used here. ``u1`` is very used, as it embed information about the type stored into the zval.

``u2`` has totally other meanings. We don't need to detail the ``u2`` field by now, simply ignore it,
we'll get back to it later.

Knowing the zval structure you can now write code making use of it::

    zval zv_ptr = /* ... get zval from somewhere */;

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
value. All the access macros have variants with a ``_P`` suffix or no suffix at all. Which one you
use depends on whether you are working on a ``zval`` or a ``zval*`` ::

    zval zv;
    zval *zv_ptr;
    zval **zv_ptr_ptr; /* very rare */

    Z_TYPE(zv);                 // = zv.type
    Z_TYPE_P(zv_ptr);           // = zv_ptr->type

Basically the ``P`` stands for "pointer". This only works until ``zval*``, i.e. there are no special macros for working
with ``zval**`` or more, as this is rarely necessary in practice (you'll just have to dereference the value first
using the ``*`` operator).

Similarly to ``Z_LVAL`` there are also macros for fetching values of all the other types. To demonstrate their usage
we'll create a simple function for dumping a zval::

    PHP_FUNCTION(dump)
    {
        zval *zv_ptr;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "z", &zv_ptr) == FAILURE) {
            return;
        }

        switch (Z_TYPE_P(zv_ptr)) {
            case IS_NULL:
                php_printf("NULL: null\n");
                break;
            case IS_TRUE:
                php_printf("BOOL: true\n");
                break;
            case IS_FALSE:
                php_printf("BOOL: false\n");
                break;
            case IS_LONG:
                php_printf("LONG: %ld\n", Z_LVAL_P(zv_ptr));
                break;
            case IS_DOUBLE:
                php_printf("DOUBLE: %g\n", Z_DVAL_P(zv_ptr));
                break;
            case IS_STRING:
                php_printf("STRING: value=\"");
                PHPWRITE(Z_STRVAL_P(zv_ptr), Z_STRLEN_P(zv_ptr));
                php_printf("\", length=%zd\n", Z_STRLEN_P(zv_ptr));
                break;
            case IS_RESOURCE:
                php_printf("RESOURCE: id=%d\n", Z_RES_HANDLE_P(zv_ptr));
                break;
            case IS_ARRAY:
                php_printf("ARRAY: hashtable=%p\n", Z_ARRVAL_P(zv_ptr));
                break;
            case IS_OBJECT:
                php_printf("OBJECT: object=%p\n", Z_OBJ_P(zv_ptr));
                break;
        }
    }

    const zend_function_entry funcs[] = {
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
    dump(new stdClass);         // OBJECT: object=0x???

The macros for accessing the values are pretty straightforward: ``Z_LVAL`` for longs, ``Z_DVAL``
for doubles. For strings ``Z_STR`` returns the actual ``zend_string *`` string, ``ZSTR_VAL`` accesses the char * into
it whereas ``Z_STRLEN`` provides us with the length. The resource ID can be fetched using ``Z_RES_HANDLE`` and the
``zend_array *`` of an array is accessed with ``Z_ARRVAL``.

When you want to access the contents of a zval you should always go through these macros, rather than directly accessing
its members. This maintains a level of abstraction and makes the intention clearer. Using the macros also serves as a
protection against changes to the internal zval representation in future PHP versions.

Setting the value
-----------------

Most of the macros introduced above just access some member of the zval structure and as such you can use them both to
read and to write the respective values. An exception is ``Z_TYPE_P``, you need to use ``Z_TYPE_INFO_P`` instead to write the type tag. As an example consider the following function, which simply returns the string
"hello world!"::

    PHP_FUNCTION(hello_world) {
        Z_TYPE_INFO_P(return_value) = IS_STRING;
        Z_STR_P(return_value) = zend_string_init("hello world!", strlen("hello world!"), 0);
    };

    /* ... */
        PHP_FE(hello_world, NULL)
    /* ... */

Running ``php -r "echo hello_world();"`` should now print ``hello world!`` to the terminal.

In the above example we set the ``return_value`` variable, which is a ``zval*`` provided by the ``PHP_FUNCTION`` macro.
We'll look at this variable in more detail in the next chapter, for now it should suffice to know that the value of this
variable will be the return value of the function. By default it is initialized to have type ``IS_NULL``.

Setting a zval value using the access macros is really straightforward, but there are some things one should keep in
mind: First of all you need to remember that the type tag determines the type of a zval. It doesn't suffice to just set
the value (via ``Z_STR_P``), you always need to set the type tag as well.

Furthermore you need to be aware of the fact that in most cases the zval "owns" its value and that the zval will have a
longer life-time than the scope in which you set its value. Sometimes this doesn't apply when dealing with temporary
zvals, but in most cases it's true.

Using the above example this means that the ``return_value`` will live on after our function body leaves (which is quite
obvious, otherwise nobody could use the return value), so it can't make use of any temporary values of the function.

Because of this we need to create a new zend_string using ``zend_string_init()``. This will create a separate copy
of the string on the heap. Because the zval "carries" its value, it will make sure to free this copy when the zval is
destroyed, or at least to decrement its refcount. This also applies to any other "complex" value of the zval. E.g.
if you set the ``zend_array*`` for an array, the zval will carry that later and release it when the zval is destroyed.
By "releasing", we mean either decrement the reference counter, or free the structure if reference counter falls to
zero. When using primitive types like integers or doubles you obviously don't need to care about this, as they are
always copied.
All those memory management steps, such as allocation, free or reference counting; are detailed in the
:doc:`memory_and_gc` chapter.

Setting the zval value is such a common task, PHP provides another set of macros for this purpose. They allow you to
set the type tag and the value at the same time. Rewriting the previous example using such a macro yields::

    PHP_FUNCTION(hello_world) {
        ZVAL_STRINGL(return_value, "hello world!", strlen("hello world!"));
    }

Furthermore we don't need to manually compute the ``strlen`` and can use the ``ZVAL_STRING`` macro (without the ``L`` at
the end) instead::

    PHP_FUNCTION(hello_world) {
        ZVAL_STRING(return_value, "hello world!");
    }

If you know the length of the string (because it was passed to you in some way) you should always make use of it via the
``ZVAL_STRINGL`` macro in order to preserve binary-safety. If you don't know the length (or know that the string doesn't
contain NUL bytes, as is usually the case with literals) you can use ``ZVAL_STRING`` instead.

Apart from ``ZVAL_STRING(L)`` there are a few more macros for setting values, which are listed in the following
example::

    ZVAL_NULL(return_value);

    ZVAL_FALSE(return_value);
    ZVAL_TRUE(return_value);

    ZVAL_LONG(return_value, 42);
    ZVAL_DOUBLE(return_value, 4.2);
    ZVAL_RES(return_value, zend_resource *);

    ZVAL_EMPTY_STRING(return_value);
    /* a special way to manage the "" empty string */

    ZVAL_STRING(return_value, "string");
    /* = ZVAL_NEW_STR(z, zend_string_init("string", strlen("string"), 0)); */

    ZVAL_STRINGL(return_value, "nul\0string", 10);
    /* = ZVAL_NEW_STR(z, zend_string_init("nul\0string", 10, 0)); */

Note that these macros will set the value, but not destroy any value that the zval might have previously held. For the
``return_value`` zval this doesn't matter because it was initialized to ``IS_NULL`` (which has no value that needs to be
freed), but in other cases you'll have to destroy the old value first using the functions described in the following
section.
