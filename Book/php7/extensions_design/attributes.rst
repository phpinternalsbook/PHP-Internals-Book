Attributes
==========

.. versionadded:: PHP 8.0

   Attributes were introduced in PHP 8.0 and are not available in PHP 7.

PHP 8.0 introduced attributes (also known as annotations in other languages). Attributes allow you to attach
structured metadata to classes, functions, methods, properties, class constants, and function parameters,
using the ``#[AttributeClass(args...)]`` syntax::

    #[Attribute]
    class MyAttr {
        public function __construct(public readonly int $value) {}
    }

    #[MyAttr(42)]
    function my_function(): void {}

This chapter explains how attributes are represented internally, how extensions can read attributes attached
to declarations, and how to define attribute classes from C.

Internal representation
------------------------

Each attribute annotation is stored as a ``zend_attribute`` struct, defined in ``Zend/zend_attributes.h``::

    typedef struct _zend_attribute {
        zend_string *name;    /* fully-qualified attribute class name */
        zend_string *lcname;  /* lowercased for lookup */
        uint32_t     flags;   /* ZEND_ATTRIBUTE_PERSISTENT | ZEND_ATTRIBUTE_STRICT_TYPES */
        uint32_t     lineno;
        uint32_t     offset;  /* 0 for class/function/property/const;
                                 1-based parameter index for parameters */
        uint32_t     argc;
        zend_attribute_arg args[1]; /* flexible array */
    } zend_attribute;

Each argument is a ``zend_attribute_arg``::

    typedef struct {
        zend_string *name;  /* argument name (NULL for positional arguments) */
        zval         value; /* the argument value as a compile-time constant zval */
    } zend_attribute_arg;

Attributes are stored on the relevant declaration as a ``HashTable *attributes`` pointer:

.. list-table::
    :header-rows: 1

    * - Declaration
      - Field
    * - Class
      - ``zend_class_entry.attributes``
    * - Function / method
      - ``zend_function.common.attributes``
    * - Property
      - ``zend_property_info.attributes``
    * - Class constant
      - ``zend_class_constant.attributes``
    * - Parameter
      - same as function, distinguished by ``zend_attribute.offset`` (1-based)

The hash table keys are the lowercased attribute class names. Multiple attributes of the same class on the
same declaration are stored under a shared key as a linked list (when the attribute class has
``ZEND_ATTRIBUTE_IS_REPEATABLE`` set) or as a single entry (otherwise).

Reading attributes from C
--------------------------

Use the ``zend_get_attribute*`` family of functions to look up attributes by name.

**On a function or method**::

    /* Look up #[MyAttr] on a function. The name must be lowercased. */
    zend_attribute *attr = zend_get_attribute_str(
        func->common.attributes,
        "myattr",
        sizeof("myattr") - 1
    );

    if (attr != NULL) {
        /* attribute is present */
        if (attr->argc >= 1) {
            zval value;
            zend_result result = zend_get_attribute_value(
                &value, attr, /* arg index */ 0, func->common.scope);

            if (result == SUCCESS) {
                /* use value ... */
                zval_ptr_dtor(&value);
            }
        }
    }

**On a class**::

    zend_attribute *attr = zend_get_attribute_str(
        ce->attributes,
        "myattr",
        sizeof("myattr") - 1
    );

**On a property**::

    zend_property_info *prop_info = zend_hash_str_find_ptr(
        &ce->properties_info, "myprop", sizeof("myprop") - 1);

    if (prop_info && prop_info->attributes) {
        zend_attribute *attr = zend_get_attribute_str(
            prop_info->attributes, "myattr", sizeof("myattr") - 1);
    }

**On a parameter** (1-based index)::

    zend_attribute *attr = zend_get_parameter_attribute_str(
        func->common.attributes,
        "myattr",
        sizeof("myattr") - 1,
        /* offset = */ 1  /* first parameter */
    );

**Evaluating attribute argument values**

Attribute arguments are stored as compile-time constant expressions. They may be literals (integers,
strings, ``true``/``false``/``null``), class constants, or constant expressions. Use
``zend_get_attribute_value()`` to resolve them to a runtime ``zval``::

    zval value;
    if (zend_get_attribute_value(&value, attr, 0, scope) == SUCCESS) {
        if (Z_TYPE(value) == IS_LONG) {
            zend_long n = Z_LVAL(value);
        } else if (Z_TYPE(value) == IS_STRING) {
            zend_string *s = Z_STR(value);
        }
        zval_ptr_dtor(&value);
    }

Attribute target flags
-----------------------

When registering an internal attribute class, you specify which declaration targets it is allowed on.
These are controlled by the ``ZEND_ATTRIBUTE_TARGET_*`` flags::

    #define ZEND_ATTRIBUTE_TARGET_CLASS        (1 << 0)
    #define ZEND_ATTRIBUTE_TARGET_FUNCTION     (1 << 1)
    #define ZEND_ATTRIBUTE_TARGET_METHOD       (1 << 2)
    #define ZEND_ATTRIBUTE_TARGET_PROPERTY     (1 << 3)
    #define ZEND_ATTRIBUTE_TARGET_CLASS_CONST  (1 << 4)
    #define ZEND_ATTRIBUTE_TARGET_PARAMETER    (1 << 5)
    #define ZEND_ATTRIBUTE_TARGET_ALL          ((1 << 6) - 1)
    #define ZEND_ATTRIBUTE_IS_REPEATABLE       (1 << 6)

Combine flags with ``|``::

    ZEND_ATTRIBUTE_TARGET_FUNCTION | ZEND_ATTRIBUTE_TARGET_METHOD

Registering an internal attribute class
-----------------------------------------

To define a built-in C extension attribute that PHP userland can use:

**Step 1: Register the class entry** (in MINIT)::

    static zend_class_entry ce;
    INIT_CLASS_ENTRY(ce, "MyExtension\\SomeAttr", myattr_methods);
    zend_class_entry *myattr_ce = zend_register_internal_class(&ce);

**Step 2: Mark it as an attribute**::

    zend_internal_attribute *int_attr = zend_internal_attribute_register(
        myattr_ce,
        ZEND_ATTRIBUTE_TARGET_FUNCTION | ZEND_ATTRIBUTE_TARGET_METHOD
    );

**Step 3: Optionally, add a validator callback**::

    int_attr->validator = my_attr_validator;

The validator is called at class-link time (when the class containing the attribute is first used).
Its signature is::

    static void my_attr_validator(zend_attribute *attr,
                                  uint32_t target,
                                  zend_class_entry *scope)
    {
        /* Validate attribute arguments. Throw a TypeError or
         * ValueError if the arguments are invalid. */
        if (attr->argc < 1) {
            zend_type_error("SomeAttr requires at least one argument");
        }
    }

Attaching attributes to internal declarations from C
-----------------------------------------------------

If you want to attach attributes to your own internal functions, properties, or class constants
programmatically from C, use the ``zend_add_*_attribute()`` helpers::

    /* Attach #[MyAttr(1)] to a function */
    zend_attribute *a = zend_add_function_attribute(
        zend_hash_str_find_ptr(EG(function_table), "my_func", sizeof("my_func") - 1),
        zend_string_init("myattr", sizeof("myattr") - 1, 1),
        /* argc */ 1
    );
    ZVAL_LONG(&a->args[0].value, 1);
    a->args[0].name = NULL; /* positional argument */

Built-in attribute class entries
----------------------------------

The engine exports the following built-in attribute class entries for use in extension code:

.. list-table::
    :header-rows: 1

    * - Variable
      - PHP class
    * - ``zend_ce_attribute``
      - ``Attribute``
    * - ``zend_ce_allow_dynamic_properties``
      - ``AllowDynamicProperties`` (PHP 8.2+)
    * - ``zend_ce_sensitive_parameter``
      - ``SensitiveParameter`` (PHP 8.2+)
    * - ``zend_ce_sensitive_parameter_value``
      - ``SensitiveParameterValue`` (PHP 8.2+)
    * - ``zend_ce_override``
      - ``Override`` (PHP 8.3+)
    * - ``zend_ce_deprecated``
      - ``Deprecated`` (PHP 8.4+)

These can be used to check whether a declaration carries a known built-in attribute, or to register
your own class as a subclass of one of them.

The ``SensitiveParameter`` attribute
--------------------------------------

.. versionadded:: PHP 8.2

PHP 8.2 added the ``#[SensitiveParameter]`` attribute, which marks a function parameter as sensitive.
When a ``Throwable`` is caught and its backtrace is inspected, argument values for parameters marked
``#[SensitiveParameter]`` are replaced with a ``SensitiveParameterValue`` object. This prevents
passwords, keys, and similar values from appearing in stack traces.

For internal functions, declare the attribute in the stub file::

    function my_login(string $username, #[\SensitiveParameter] string $password): bool {}

``gen_stub.php`` will emit the attribute in the generated arginfo. The engine checks for this attribute
automatically when building exception backtraces.
