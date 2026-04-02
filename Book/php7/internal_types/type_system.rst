The type system
===============

.. versionadded:: PHP 8.0

   The ``zend_type`` structure described here was introduced in PHP 8.0. PHP 7 used separate
   ``type_hint`` and ``class_name`` fields in ``zend_internal_arg_info``. Union types, intersection
   types, and DNF types are PHP 8.0+ features.

PHP 8 introduced a significantly more expressive type system. From a user perspective, PHP 8.0 added union
types (``int|string``), PHP 8.1 added intersection types (``Countable&Iterator``) and the ``never`` return
type, and PHP 8.2 added standalone ``null``, ``true``, and ``false`` types as well as DNF (disjunctive normal
form) types (``(Countable&Iterator)|null``).

Internally, all of this is represented through the ``zend_type`` structure and the ``MAY_BE_*`` bitmask
family. This chapter explains how these work and how to use them in extension code.

The ``zend_type`` structure
----------------------------

Every type hint in PHP -- whether on a function parameter, return value, or property -- is represented by a
``zend_type`` value. The structure is defined in ``Zend/zend_types.h``::

    typedef struct {
        void    *ptr;
        uint32_t type_mask;
    } zend_type;

The two fields serve different roles depending on what type is being represented:

* **``type_mask``** is a bitmask. The lower 18 bits are ``MAY_BE_*`` flags (one bit per primitive type).
  The upper bits encode metadata: whether ``ptr`` points to a class name or type list, whether the type
  list is a union or intersection, and so on.

* **``ptr``** points to auxiliary data when needed. For a class/interface type it points to a
  ``zend_string*`` (or a ``const char*`` for internal functions). For union and intersection types it
  points to a ``zend_type_list``.

For pure primitive types (e.g. ``int``, ``string``, ``?bool``), ``ptr`` is ``NULL`` and the entire type
is encoded in ``type_mask``.

The ``zend_type_list`` structure
---------------------------------

Union and intersection types use a type list::

    typedef struct {
        uint32_t  num_types;
        zend_type types[1]; /* flexible array */
    } zend_type_list;

Each element of the ``types`` array is itself a ``zend_type``, which may represent a primitive type, a
named class type, or (for DNF types) another list. The ``type_mask`` of the enclosing ``zend_type``
carries the ``_ZEND_TYPE_UNION_BIT`` or ``_ZEND_TYPE_INTERSECTION_BIT`` flag to indicate which kind
of compound type this is.

The ``MAY_BE_*`` bitmask family
--------------------------------

The lower 18 bits of ``type_mask`` (bits 0-17) are ``MAY_BE_*`` flags, one per PHP type. These flags are
also used extensively by the optimizer and JIT for type inference, though some bits are only valid in type
declarations and not in the optimizer's type information. They are defined in ``Zend/zend_type_info.h``::

    #define MAY_BE_UNDEF     (1 << IS_UNDEF)    /* bit 0  */
    #define MAY_BE_NULL      (1 << IS_NULL)      /* bit 1  */
    #define MAY_BE_FALSE     (1 << IS_FALSE)     /* bit 2  */
    #define MAY_BE_TRUE      (1 << IS_TRUE)      /* bit 3  */
    #define MAY_BE_BOOL      (MAY_BE_FALSE|MAY_BE_TRUE)
    #define MAY_BE_LONG      (1 << IS_LONG)      /* bit 4  */
    #define MAY_BE_DOUBLE    (1 << IS_DOUBLE)    /* bit 5  */
    #define MAY_BE_STRING    (1 << IS_STRING)    /* bit 6  */
    #define MAY_BE_ARRAY     (1 << IS_ARRAY)     /* bit 7  */
    #define MAY_BE_OBJECT    (1 << IS_OBJECT)    /* bit 8  */
    #define MAY_BE_RESOURCE  (1 << IS_RESOURCE)  /* bit 9  */
    #define MAY_BE_ANY       (MAY_BE_NULL|MAY_BE_FALSE|MAY_BE_TRUE|MAY_BE_LONG| \
                              MAY_BE_DOUBLE|MAY_BE_STRING|MAY_BE_ARRAY|          \
                              MAY_BE_OBJECT|MAY_BE_RESOURCE)
    #define MAY_BE_REF       (1 << IS_REFERENCE) /* bit 10 */

The following bits exist at positions 11-17 and are only meaningful in type declarations (not in the
optimizer's ``MAY_BE_*`` usage)::

    #define MAY_BE_CALLABLE  (1 << IS_CALLABLE)
    #define MAY_BE_VOID      (1 << IS_VOID)
    #define MAY_BE_NEVER     (1 << IS_NEVER)
    #define MAY_BE_STATIC    (1 << IS_STATIC)

Notice that ``MAY_BE_ANY`` does not include ``MAY_BE_UNDEF`` or ``MAY_BE_REF``. The ``mixed`` type maps
to ``MAY_BE_ANY``, not ``MAY_BE_ANY | MAY_BE_NULL`` -- ``null`` is already in ``MAY_BE_ANY``.

``type_mask`` bit layout
-------------------------

The 32 bits of ``type_mask`` are partitioned as follows:

.. list-table::
    :header-rows: 1
    :widths: 10 30 60

    * - Bits
      - Name
      - Purpose
    * - 0--17
      - ``MAY_BE_*``
      - Primitive type flags (see above)
    * - 18
      - ``_ZEND_TYPE_UNION_BIT``
      - ``ptr`` points to a union type list
    * - 19
      - ``_ZEND_TYPE_INTERSECTION_BIT``
      - ``ptr`` points to an intersection type list
    * - 20
      - ``_ZEND_TYPE_ARENA_BIT``
      - Type list is arena-allocated (persistent)
    * - 21
      - ``_ZEND_TYPE_ITERABLE_BIT``
      - BC compatibility flag for the ``iterable`` pseudo-type
    * - 22
      - ``_ZEND_TYPE_LIST_BIT``
      - ``ptr`` is a ``zend_type_list*``
    * - 23
      - ``_ZEND_TYPE_LITERAL_NAME_BIT``
      - ``ptr`` is a ``const char*`` class name (internal functions)
    * - 24
      - ``_ZEND_TYPE_NAME_BIT``
      - ``ptr`` is a ``zend_string*`` class name
    * - 25--31
      - Extra flags
      - Per-argument flags (pass-by-ref, variadic, tentative; see arginfo)

The bit at position 1 (``MAY_BE_NULL``) doubles as the "nullable" flag: checking
``type_mask & _ZEND_TYPE_NULLABLE_BIT`` is equivalent to checking ``type_mask & MAY_BE_NULL``.

Inspection macros
-----------------

The engine provides a complete set of macros to inspect a ``zend_type`` without accessing the struct
members directly. Always use these macros rather than reading ``ptr`` and ``type_mask`` directly.

**Presence checks**::

    ZEND_TYPE_IS_SET(t)          /* is any type hint present at all? */
    ZEND_TYPE_IS_ONLY_MASK(t)    /* only primitive MAY_BE_* bits, no ptr */
    ZEND_TYPE_IS_COMPLEX(t)      /* has a class name or type list pointer */

**Kind checks**::

    ZEND_TYPE_HAS_NAME(t)        /* ptr is a zend_string* class name */
    ZEND_TYPE_HAS_LITERAL_NAME(t)/* ptr is a const char* class name */
    ZEND_TYPE_HAS_LIST(t)        /* ptr is a zend_type_list* */
    ZEND_TYPE_IS_UNION(t)        /* compound type is a union */
    ZEND_TYPE_IS_INTERSECTION(t) /* compound type is an intersection */

**Nullable / mask access**::

    ZEND_TYPE_ALLOW_NULL(t)      /* is null allowed? */
    ZEND_TYPE_PURE_MASK(t)       /* MAY_BE_* bits only (bits 0-17) */
    ZEND_TYPE_FULL_MASK(t)       /* entire type_mask value */

**Pointer access** (use only after the corresponding check)::

    ZEND_TYPE_NAME(t)            /* (zend_string *) class name */
    ZEND_TYPE_LITERAL_NAME(t)    /* (const char *) class name */
    ZEND_TYPE_LIST(t)            /* (zend_type_list *) compound type list */

**Primitive type check**::

    ZEND_TYPE_CONTAINS_CODE(t, IS_LONG)   /* does type include IS_LONG? */
    ZEND_TYPE_CONTAINS_CODE(t, IS_STRING) /* does type include IS_STRING? */

**Iteration over compound types**::

    zend_type *type_ptr;

    ZEND_TYPE_FOREACH(my_type, type_ptr) {
        /* *type_ptr is each constituent zend_type */
    } ZEND_TYPE_FOREACH_END();

    /* For a known zend_type_list: */
    ZEND_TYPE_LIST_FOREACH(list_ptr, type_ptr) {
        /* *type_ptr is each element */
    } ZEND_TYPE_LIST_FOREACH_END();

Construction macros
--------------------

When writing arginfo by hand (or when understanding what ``gen_stub.php`` generates), the following
construction macros are used:

**No type hint**::

    ZEND_TYPE_INIT_NONE(extra_flags)

**Single primitive type** (the most common case)::

    ZEND_TYPE_INIT_CODE(IS_LONG, /* allow_null */ 0, /* extra_flags */ 0)
    ZEND_TYPE_INIT_CODE(IS_STRING, 1, 0)  /* nullable string */
    ZEND_TYPE_INIT_CODE(_IS_BOOL, 0, 0)   /* bool */
    ZEND_TYPE_INIT_CODE(IS_VOID, 0, 0)    /* void return */

**Bitmask of primitives** (for unions of primitive types)::

    ZEND_TYPE_INIT_MASK(MAY_BE_STRING | MAY_BE_FALSE)
    ZEND_TYPE_INIT_MASK(MAY_BE_LONG | MAY_BE_NULL)

**Class type**::

    /* For internal functions using a const char* name: */
    ZEND_TYPE_INIT_CLASS_CONST("SomeClass", /* allow_null */ 0, 0)

    /* For user-defined functions using a zend_string* name: */
    ZEND_TYPE_INIT_CLASS(name_zstr, 0, 0)

    /* Class + primitive union (e.g. SomeClass|false): */
    ZEND_TYPE_INIT_CLASS_CONST_MASK("SomeClass", MAY_BE_FALSE)

**Compound type (union or intersection)**::

    ZEND_TYPE_INIT_UNION(list_ptr, extra_flags)
    ZEND_TYPE_INIT_INTERSECTION(list_ptr, extra_flags)

Representing common PHP 8 types
---------------------------------

The table below shows how common PHP 8 type declarations map to ``zend_type`` internal representation:

.. list-table::
    :header-rows: 1

    * - PHP type declaration
      - ``type_mask`` value
      - ``ptr``
    * - ``int``
      - ``MAY_BE_LONG``
      - ``NULL``
    * - ``?int``
      - ``MAY_BE_LONG | MAY_BE_NULL``
      - ``NULL``
    * - ``string|false``
      - ``MAY_BE_STRING | MAY_BE_FALSE``
      - ``NULL``
    * - ``mixed``
      - ``MAY_BE_ANY``
      - ``NULL``
    * - ``void``
      - ``MAY_BE_VOID``
      - ``NULL``
    * - ``never``
      - ``MAY_BE_NEVER``
      - ``NULL``
    * - ``bool``
      - ``MAY_BE_BOOL``
      - ``NULL``
    * - ``callable``
      - ``MAY_BE_CALLABLE``
      - ``NULL``
    * - ``Foo``
      - ``_ZEND_TYPE_LITERAL_NAME_BIT``
      - ``(const char *) "Foo"``
    * - ``?Foo``
      - ``_ZEND_TYPE_LITERAL_NAME_BIT | MAY_BE_NULL``
      - ``(const char *) "Foo"``
    * - ``int|string``
      - ``_ZEND_TYPE_LIST_BIT | _ZEND_TYPE_UNION_BIT``
      - ``(zend_type_list *)``
    * - ``Countable&Iterator``
      - ``_ZEND_TYPE_LIST_BIT | _ZEND_TYPE_INTERSECTION_BIT``
      - ``(zend_type_list *)``

Checking types at runtime
--------------------------

To check whether a given ``zval`` satisfies a ``zend_type`` constraint, use ``zend_check_type()`` from
``Zend/zend_types.h``. In practice, extension code rarely needs to do this manually -- the parameter
parsing macros and the engine's type coercion handle it automatically when a PHP function is called.

However, if you are implementing a custom property handler or need type checking outside of the normal
call mechanism, you can use::

    bool zend_value_instanceof_static(zval *zv);
    bool zend_check_type(zend_type *type, zval *arg, void **cache_slot,
                         zend_class_entry *scope, bool is_return_type,
                         bool is_internal);

Arginfo and property types
---------------------------

``zend_type`` is used in three places:

1. **Function/method arginfo** (parameter and return types) -- via ``zend_arg_info.type`` /
   ``zend_internal_arg_info.type``.

2. **Property type declarations** -- via ``zend_property_info.type``.

3. **Class constant type declarations** (PHP 8.3+) -- via ``zend_class_constant.type``.

The :doc:`stub files chapter <../extensions_design/stub_files>` explains how to declare all of these
in extension code using the stub file approach.

The ``iterable`` pseudo-type
------------------------------

The ``iterable`` pseudo-type (equivalent to ``array|Traversable``) is represented with the
``_ZEND_TYPE_ITERABLE_BIT`` flag for backward compatibility. In PHP 8.2 and later, ``iterable`` is a
compile-time alias for ``array|Traversable`` in user-defined functions. In arginfo for internal functions,
you can use ``IS_ITERABLE`` with ``ZEND_TYPE_INIT_CODE`` and it will be handled correctly::

    ZEND_TYPE_INIT_CODE(IS_ITERABLE, 0, 0)
