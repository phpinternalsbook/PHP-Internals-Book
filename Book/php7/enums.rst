Enums
=====

.. versionadded:: PHP 8.1

   Enums were introduced in PHP 8.1 and are not available in PHP 7.

PHP 8.1 introduced enums as a first-class language construct. Enums represent a fixed set of values and
provide type safety that constants cannot. PHP supports two kinds of enums:

* **Pure (unit) enums** -- cases have no associated value; they are identified solely by their name.
* **Backed enums** -- each case has an associated scalar value (``int`` or ``string``).

This chapter explains how enums are represented in the engine, how they compare to regular classes
internally, and how to define and use internal enums from C extension code.

Overview
--------

Enums are implemented on top of the existing class/object system. There is no separate ``zend_enum``
struct. Instead, enums are ``zend_class_entry`` instances with the ``ZEND_ACC_ENUM`` flag set. Each enum
case is stored as a class constant of a special kind (``ZEND_CLASS_CONST_IS_CASE``), whose value is a
singleton ``zend_object``.

The key implications are:

* Enum case objects can be stored in zvals like any other object.
* You can use ``instanceof`` to check if a value is of a given enum type.
* All the standard object handler infrastructure applies.
* Enum case objects are singletons: two references to the same case are always ``===``.

Enum class entry flags
-----------------------

Two fields on ``zend_class_entry`` distinguish enums from regular classes:

``ce->ce_flags & ZEND_ACC_ENUM``
    Set on any enum class.

``ce->enum_backing_type``
    ``IS_UNDEF`` for pure enums, ``IS_LONG`` for int-backed enums, ``IS_STRING`` for string-backed enums.

Case objects
-------------

Each enum case is a ``zend_object`` instance. The object stores two properties by numeric index:

* **Slot 0**: The case name as a ``zend_string``. Access with ``zend_enum_fetch_case_name()``.
* **Slot 1**: The backing value (backed enums only). Access with ``zend_enum_fetch_case_value()``.

These are accessed via ``OBJ_PROP_NUM(zobj, n)``, which indexes the object's inline property table
by position.

Accessing case properties::

    zend_object *case_obj = /* obtain a case object */;

    /* Name is always available */
    zval *name_zv = zend_enum_fetch_case_name(case_obj);
    zend_string *name = Z_STR_P(name_zv);  /* e.g. "Active" */

    /* Value is only available for backed enums */
    if (case_obj->ce->enum_backing_type != IS_UNDEF) {
        zval *value_zv = zend_enum_fetch_case_value(case_obj);
        if (case_obj->ce->enum_backing_type == IS_LONG) {
            zend_long v = Z_LVAL_P(value_zv);
        } else {
            zend_string *v = Z_STR_P(value_zv);
        }
    }

The cases table
----------------

All cases are stored as class constants in ``CE_CONSTANTS_TABLE(ce)``. Each constant has
``ZEND_CLASS_CONST_IS_CASE`` set in its flags. The constant value is a ``zval`` of type ``IS_OBJECT``
pointing to the singleton case object.

Iterate over all cases::

    zend_string *case_name;
    zend_class_constant *c;

    ZEND_HASH_FOREACH_STR_KEY_PTR(CE_CONSTANTS_TABLE(my_enum_ce), case_name, c) {
        if (ZEND_CLASS_CONST_FLAGS(c) & ZEND_CLASS_CONST_IS_CASE) {
            zval *case_zv = &c->value;
            zend_object *case_obj = Z_OBJ_P(case_zv);
            /* ... */
        }
    } ZEND_HASH_FOREACH_END();

The backed enum table
---------------------

For backed enums, a reverse-lookup ``HashTable`` (accessible via ``CE_BACKED_ENUM_TABLE(ce)``) maps
backing values to case names. This is what powers ``MyEnum::from()`` and ``MyEnum::tryFrom()``.

Defining an internal enum from C
----------------------------------

Extensions can define enum types using ``zend_register_internal_enum()``.

**Register the enum class**::

    zend_class_entry *my_enum_ce = zend_register_internal_enum(
        "MyExtension\\Status",
        IS_STRING,           /* backing type: IS_UNDEF, IS_LONG, or IS_STRING */
        my_enum_methods      /* additional methods, or NULL */
    );

This handles everything automatically: sets ``ZEND_ACC_ENUM``, allocates the backed enum table,
and registers the built-in methods ``cases()``, ``from()``, and ``tryFrom()``.

**Add enum cases**::

    /* For a string-backed enum */
    zval val;

    ZVAL_STRING(&val, "active");
    zend_enum_add_case_cstr(my_enum_ce, "Active", &val);
    zval_ptr_dtor(&val);

    ZVAL_STRING(&val, "inactive");
    zend_enum_add_case_cstr(my_enum_ce, "Inactive", &val);
    zval_ptr_dtor(&val);

For a pure enum, pass ``NULL`` as the value::

    zend_enum_add_case_cstr(my_unit_enum_ce, "CaseA", NULL);
    zend_enum_add_case_cstr(my_unit_enum_ce, "CaseB", NULL);

For an int-backed enum::

    ZVAL_LONG(&val, 1);
    zend_enum_add_case_cstr(my_int_enum_ce, "One", &val);

**Retrieve a case by name**::

    zend_object *case_obj = zend_enum_get_case_cstr(my_enum_ce, "Active");
    if (case_obj) {
        /* Use the case singleton */
    }

**Retrieve a case by backing value** (implements ``from()``/``tryFrom()`` semantics)::

    zend_object *result = NULL;
    zend_result rc = zend_enum_get_case_by_value(
        &result,
        my_enum_ce,
        /* long_key */ 0,           /* used only if backing type is IS_LONG */
        /* string_key */ ZSTR_INIT_LITERAL("active", 0),
        /* try_from */ true         /* false = throw ValueError on not found */
    );

    if (rc == SUCCESS && result != NULL) {
        /* result is the case object */
    }

The full public API
--------------------

The complete C API for enums is declared in ``Zend/zend_enum.h``:

.. list-table::
    :header-rows: 1

    * - Function
      - Description
    * - ``zend_register_internal_enum(name, type, methods)``
      - Register a new internal enum class.
    * - ``zend_enum_add_case(ce, name_str, value_zv)``
      - Add a case (``zend_string*`` name, nullable ``zval*`` value).
    * - ``zend_enum_add_case_cstr(ce, name, value_zv)``
      - Add a case (``const char*`` name).
    * - ``zend_enum_get_case(ce, name)``
      - Look up a case by ``zend_string*`` name.
    * - ``zend_enum_get_case_cstr(ce, name)``
      - Look up a case by ``const char*`` name.
    * - ``zend_enum_get_case_by_value(result, ce, long_key, str_key, try_from)``
      - Look up a case by backing value.
    * - ``zend_enum_fetch_case_name(zobj)``
      - Return ``zval*`` for the ``name`` property of a case object.
    * - ``zend_enum_fetch_case_value(zobj)``
      - Return ``zval*`` for the ``value`` property (backed enums only).
    * - ``zend_enum_new(result, ce, case_name, backing_value_zv)``
      - Low-level: allocate a new case object (use ``zend_enum_add_case`` instead).

Using an enum case as a function argument
------------------------------------------

When a function in your extension accepts an enum value, declare the parameter type in the stub file
using the enum class name::

    function set_status(MyExtension\Status $status): void {}

In the function body, receive it as a ``zend_object*`` and verify it is the expected enum::

    PHP_FUNCTION(set_status)
    {
        zend_object *status_obj;

        ZEND_PARSE_PARAMETERS_START(1, 1)
            Z_PARAM_OBJ_OF_CLASS(status_obj, my_enum_ce)
        ZEND_PARSE_PARAMETERS_END();

        /* Get the string backing value */
        zval *value = zend_enum_fetch_case_value(status_obj);
        zend_string *status_str = Z_STR_P(value);

        /* ... */
    }

Object identity and comparison
--------------------------------

Enum cases are singletons. The same case always yields the same ``zend_object*`` pointer. You can
compare two enum values with ``==`` at the pointer level, or use the standard ``zend_objects_compare``
which the enum's ``compare`` object handler delegates to.

Do not use ``clone`` on enum cases -- the ``clone_obj`` handler is set to ``NULL``, so attempting to
clone an enum case throws an ``Error``.
