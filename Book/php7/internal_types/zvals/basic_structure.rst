Basic structure
===============

A zval (short for "Zend value") represents an arbitrary PHP value. As such it is likely the most important structure in
all of PHP and you'll be working with it a lot. This section describes the basic concepts behind zvals and their use.

Types and values
----------------

Among other things, every zval stores some value and the type this value has. This is necessary because PHP is a
dynamically typed language and as such variable types are only known at run-time and not at compile-time. Furthermore,
the type can change during the life of a zval, so if the zval previously stored an integer it may contain a string at a
later point in time.

The type is stored as an integer tag, which can take one of several values. Some values correspond to the eight
types available in PHP, others are used for internal engine purposes only. These values are referred to using constants
of the form ``IS_TYPE``. E.g. ``IS_NULL`` corresponds to the null type and ``IS_STRING`` corresponds to the string type.

The actual value is stored in a union, which is defined as follows::

    typedef union _zend_value {
        zend_long         lval;    // For IS_LONG
        double            dval;    // For IS_DOUBLE
        zend_refcounted  *counted;
        zend_string      *str;     // For IS_STRING
        zend_array       *arr;     // For IS_ARRAY
        zend_object      *obj;     // For IS_OBJECT
        zend_resource    *res;     // For IS_RESOURCE
        zend_reference   *ref;     // For IS_REFERENCE
        zend_ast_ref     *ast;     // For IS_CONSTANT_AST (special)
        zval             *zv;      // For IS_INDIRECT (special)
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

Booleans use either the ``IS_TRUE`` or ``IS_FALSE`` types and don't need to store a value either. PHP internally
represents true and false as separate types for efficiency reasons, even though these are considered values from a
user perspective. There also exists an ``_IS_BOOL`` type, however it is never used as a zval type. It is used
internally to indicate casts to boolean and similar purposes.

For storing numbers PHP provides the types ``IS_LONG`` and ``IS_DOUBLE``, which make use of the ``zend_long lval`` and
``double dval`` members respectively. The former is used to store integers, whereas the latter stores floating point
numbers.

There are some things that one should be aware of about the ``zend_long`` type: Firstly, this is a signed integer type,
i.e. it can store both positive and negative integers, but is commonly not well suited for doing bitwise operations.
Secondly, ``zend_long`` is **not** the same as ``long``, because it abstracts away platform differences. ``zend_long``
is always 4 bytes large on 32-bit platorms and 8 bytes large on 64-bit platforms, even if the ``long`` type may have
a different size.

For this reason, is is important to use macros written specifically for use with ``zend_long``, such as
``SIZEOF_ZEND_LONG`` or ``ZEND_LONG_MAX``. You can find more relevant macros in
`Zend/zend_long.h <https://github.com/php/php-src/blob/1a0fa12753931dba9908161df0f63feb6d0ba025/Zend/zend_long.h>`_.

The ``double`` type used to store floating point numbers is an 8-byte value following the IEEE-754 specification.
The details of this format won't be discussed here, but you should at least be aware of the fact that this type has
limited precision and commonly doesn't store the exact value you want.

The remaining four types will only be mentioned here quickly and discussed in greater detail in their own chapters:

Strings (``IS_STRING``) are stored in a ``zend_string`` structure, which combines the string length and the string
constants in a single allocation. You will find more information about the ``zend_string`` structure and its
dedicated API in the :doc:`string <../strings>` chapter.

Arrays use the ``IS_ARRAY`` type tag and are stored in the ``zend_array *arr`` member. How the ``HashTable`` structure
works will be discussed in the :doc:`Hashtables <../hashtables>` chapter.

Objects (``IS_OBJECT``) use the ``zend_object *obj`` member. PHP's class and object system will be described in the
:doc:`objects <../objects>` chapter.

Resources (``IS_RESOURCE``) are use the ``zend_resource *res`` member. Resources are covered in the
:doc:`Resources <../zend_resources>` chapter.

To summarize, here's a table with all the available "normal" type tags and the corresponding storage location for
their values:

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

There are a number of additional types that do not have a directly corresponding userland type, and are only used
internally. Of these, ``IS_UNDEF`` and ``IS_REFERENCE`` are the only types you will encounter routinely.

The ``IS_UNDEF`` type is used to indicate an uninitialized zval. This type tag has a value of zero, so zeroing out
a zval using ``memset`` will result in an ``UNDEF`` zval. The exact meaning of ``IS_UNDEF`` depends on the context,
for example it can indicate an unintialized/unset object property, or an unused hashtable bucket.

The ``IS_REFERENCE`` type in conjunction with the ``zend_reference *ref`` member is used to represent a PHP
reference. While from a userland perspective references are not a separate type, internally references are represented
as a wrapper around another zval, that can be shared by multiple places.

The ``zend_refcounted *counted`` member accesses a common header for all reference-counted types, including strings,
arrays, objects, resources and references. How this works is discussed in the :doc:`memory management <memory_management>` chapter.

The ``IS_CONSTANT_AST`` type and ``zend_ast_ref *ast`` member are used to store unevaluated constant expression abstract syntax trees (ASTs). It can occur only in specific places, such as property default values. ASTs will be discussed
in the :doc:`compiler <../../zend_engine/zend_compiler>` chapter.

The ``IS_INDIRECT`` type and ``zval *zv`` member are used to store a direct pointer to another zval. This is used
primarily for symbol types and dynamic property tables, in order to point to an actual value stored elsewhere.

The ``IS_PTR`` type together with the ``void *ptr`` field are used to store an arbitrary pointer. In C, any pointer
type can be converted into ``void *`` and the other way around. This is used to store pointers in places that normally
only accept zvals, such as hashtable values.

The ``zend_class_entry *ce`` and ``zend_function *func`` members just specify a more precise type, but otherwise
serve the same purpose as ``ptr``.

The zval struct
---------------

Let's now have a look at how the ``zval`` struct actually looks like::

    struct _zval_struct {
        zend_value value;
        union {
            uint32_t type_info;
            struct {
                ZEND_ENDIAN_LOHI_3(
                    zend_uchar    type,
                    zend_uchar    type_flags,
                    union {
                        uint16_t  extra;
                    } u)
            } v;
        } u1;
        union {
            uint32_t next;                 /* hash collision chain */
            uint32_t cache_slot;           /* cache slot (for RECV_INIT) */
            uint32_t opline_num;           /* opline number (for FAST_CALL) */
            uint32_t lineno;               /* line number (for ast nodes) */
            uint32_t num_args;             /* arguments number for EX(This) */
            uint32_t fe_pos;               /* foreach position */
            uint32_t fe_iter_idx;          /* foreach iterator index */
            uint32_t access_flags;         /* class constant access flags */
            uint32_t property_guard;       /* single property guard */
            uint32_t constant_flags;       /* constant flags */
            uint32_t extra;                /* not further specified */
        } u2;
    };

This structure looks a bit more complicated than it really is. At its core, it stores an 8 byte ``value`` and a
single byte ``type`` tag, both of which we have already discussed above.

This would theoretically leave us with a zval size of 9 bytes. However, to allow efficient access, it is necessary
to align the structure size of an 8 byte boundary, such that the total size becomes 16 bytes. As the additional space
will be used anyway, PHP makes some use of the "wasted" space:

The ``type`` tag is part of a larger ``type_info`` structure, which additionally stores ``type_flags``. As of PHP 7.4
there are only two type flags: ``IS_TYPE_REFCOUNTED`` indicates that the value is reference-counted, while
``IS_TYPE_COLLECTABLE`` indicates that it participates in circular garbage collection. We will discuss both of these
in the future.

The ``u2`` member is a 32-bit space to store arbitrary data, and is used for different purposes depending on context.
Hashtables use it to store the collision resolution chain, but as the above comments indicate, there are many other
usages as well. It should be noted that standard zval macros will never modify or copy the ``u2`` field.

The ``u1.v.u.extra`` field that is part of the type is very rarely used to also store additional information.
However, use of this field is only possible in very specific circumstances, as PHP will usually assume that it is
zero.

Access macros
-------------

Knowing the zval structure you can now write code making use of it::

    zval *zv_ptr = /* ... get zval from somewhere */;

    if (zv_ptr->u1.v.type == IS_LONG) {
        php_printf("Zval is a long with value " ZEND_LONG_FMT "\n", zv_ptr->value.lval);
    } else /* ... handle other types */

While the above code works, this is not the idiomatic way to write it. It directly accesses the zval members rather
than using a special set of access macros for this purpose::

    zval *zv_ptr = /* ... */;

    if (Z_TYPE_P(zv_ptr) == IS_LONG) {
        php_printf("Zval is a long with value " ZEND_LONG_FMT "\n", Z_LVAL_P(zv_ptr));
    } else /* ... */

The above code uses the ``Z_TYPE_P()`` macro for retrieving the type tag and ``Z_LVAL_P()`` to get the long (integer)
value. All the access macros have variants with a ``_P`` (for "pointer") suffix or no suffix at all. Which one you
use depends on whether you are working on a ``zval`` or a ``zval*`` ::

    zval zv;
    zval *zv_ptr;

    Z_TYPE(zv);       // Same as Z_TYPE_P(&zv).
    Z_TYPE_P(zv_ptr); // Same as Z_TYPE(*zv_ptr).

Similarly to ``Z_LVAL`` there are also macros for fetching values of all the other types. To demonstrate their usage
we'll create a simple function for dumping a zval::

    PHP_FUNCTION(dump)
    {
        zval *zv_ptr;

        if (zend_parse_parameters(ZEND_NUM_ARGS(), "z", &zv_ptr) == FAILURE) {
            return;
        }

    try_again:
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
            case IS_REFERENCE:
                // For references, remove the reference wrapper and try again.
                // Yes, you are allowed to use goto for this purpose!
                php_printf("REFERENCE: ");
                zv_ptr = Z_REFVAL_P(zv_ptr);
                goto try_again;
            EMPTY_SWITCH_DEFAULT_CASE() // Assert that all types are handled.
        }
    }

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

The following table summarizes the most commonly used accessor macros, though there are quite a few more than that.

.. list-table::
    :header-rows: 1
    :widths: 15 20 20 45

    * - Macro
      - Returned type
      - Required zval type
      - Description
    * - ``Z_TYPE``
      - ``unsigned char``
      -
      - Type of the zval. One of the ``IS_*`` constants.
    * - ``Z_LVAL``
      - ``zend_long``
      - ``IS_LONG``
      - Integer value.
    * - ``Z_DVAL``
      - ``double``
      - ``IS_DOUBLE``
      - Floating-point value.
    * - ``Z_STR``
      - ``zend_string *``
      - ``IS_STRING``
      - Pointer to full ``zend_string`` structure.
    * - ``Z_STRVAL``
      - ``char *``
      - ``IS_STRING``
      - String contents of the ``zend_string`` struct.
    * - ``Z_STRLEN``
      - ``size_t``
      - ``IS_STRING``
      - String length of the ``zend_string`` struct.
    * - ``Z_ARR``
      - ``HashTable *``
      - ``IS_ARRAY``
      - Pointer to ``HashTable`` structure.
    * - ``Z_ARRVAL``
      - ``HashTable *``
      - ``IS_ARRAY``
      - Alias of ``Z_ARR``.
    * - ``Z_OBJ``
      - ``zend_object *``
      - ``IS_OBJECT``
      - Pointer to ``zend_object`` structure.
    * - ``Z_OBJCE``
      - ``zend_class_entry *``
      - ``IS_OBJECT``
      - Class entry of the object.
    * - ``Z_RES``
      - ``zend_resource *``
      - ``IS_RESOURCE``
      - Pointer to ``zend_resource`` structure.
    * - ``Z_REF``
      - ``zend_reference *``
      - ``IS_REFERENCE``
      - Pointer to ``zend_reference`` structure.
    * - ``Z_REFVAL``
      - ``zval *``
      - ``IS_REFERENCE``
      - Pointer to the zval the reference wraps.

When you want to access the contents of a zval, you should always go through these macros, rather than directly
accessing its members. This maintains a level of abstraction and will, to some degree, insulate you from changes in
the implementation.
