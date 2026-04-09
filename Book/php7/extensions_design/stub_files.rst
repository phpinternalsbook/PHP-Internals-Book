Stub files
==========

.. versionadded:: PHP 8.0

   Stub files are a PHP 8.0+ feature. PHP 7 extensions must write arginfo by hand using the
   ``ZEND_BEGIN_ARG_*`` macro family directly.

Before PHP 8, declaring function signatures for internal (C extension) functions required writing
``zend_internal_arg_info`` arrays by hand using a family of ``ZEND_ARG_*`` and ``ZEND_BEGIN_ARG_*`` macros.
This was error-prone and verbose -- especially for functions with union types, nullable types, or many
parameters.

PHP 8 introduces **stub files**: plain PHP files (``*.stub.php``) that describe function, class, interface,
and enum signatures using normal PHP 8 syntax. A code generator, ``build/gen_stub.php`` from the PHP source
tree, reads these stub files and produces the corresponding ``*_arginfo.h`` C header. The generated header
is what you include in your extension.

This approach means you write natural PHP type hints once and get correct, complete arginfo for free.

.. note:: As of PHP 8.0, all internal functions must declare arginfo. Using stub files is the recommended
          way to satisfy this requirement. Undeclared functions produce a warning at startup.

Stub file syntax
-----------------

A stub file is a valid PHP file, but with empty function bodies and special constant placeholder values.
Here is a minimal example, ``myext.stub.php``::

    <?php

    /** @generate-class-entries */

    function myext_hello(string $name = "world"): string {}

    function myext_add(int $a, int $b): int {}

    function myext_parse(string $input, int $flags = 0): array|false {}

Key rules:

* Function bodies are always empty ``{}``.
* Types use normal PHP 8 syntax: ``?T``, ``T|U``, ``T&U``, ``(T&U)|null``.
* Default values are written as PHP expressions. ``gen_stub.php`` stores the string representation of the
  default for use in reflection; the actual default value logic is still in your C code.
* Constants must be declared with a value of ``UNKNOWN`` because their values come from C ``#define``
  directives and are not known at stub-parse time: ``const MY_FLAG = UNKNOWN;``
* Use ``/** @generate-class-entries */`` on classes/interfaces/enums to instruct ``gen_stub.php`` to emit
  the ``register_class_*()`` function that registers the class.

Generating the arginfo header
------------------------------

Run ``gen_stub.php`` from the PHP source tree, passing your stub file as the argument::

    php /path/to/php-src/build/gen_stub.php ext/myext/myext.stub.php

This writes (or updates) ``ext/myext/myext_arginfo.h``. The generated header contains:

* A ``static const zend_internal_arg_info`` array for each function.
* ``ZEND_FUNCTION(name)`` forward declarations.
* A ``static const zend_function_entry ext_functions[]`` table.
* ``register_class_*()`` functions for any declared classes.
* A stub hash comment so you can detect when regeneration is needed.

The generated file should be committed to your repository alongside the stub file. Regenerate it whenever
you change the stub.

A complete example
-------------------

Suppose your stub file is::

    <?php

    function myext_compress(string $data, int $level = -1): string|false {}

    function myext_decompress(string $data): string {}

The generated ``myext_arginfo.h`` will look like::

    /* This is a generated file, edit the .stub.php file instead.
     * Stub hash: <sha1 of stub file> */

    ZEND_BEGIN_ARG_WITH_RETURN_TYPE_MASK_EX(arginfo_myext_compress, 0, 1,
            MAY_BE_STRING|MAY_BE_FALSE)
        ZEND_ARG_TYPE_INFO(0, data, IS_STRING, 0)
        ZEND_ARG_TYPE_INFO_WITH_DEFAULT_VALUE(0, level, IS_LONG, 0, "-1")
    ZEND_END_ARG_INFO()

    ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_myext_decompress, 0, 1,
            IS_STRING, 0)
        ZEND_ARG_TYPE_INFO(0, data, IS_STRING, 0)
    ZEND_END_ARG_INFO()

    ZEND_FUNCTION(myext_compress);
    ZEND_FUNCTION(myext_decompress);

    static const zend_function_entry ext_functions[] = {
        ZEND_FE(myext_compress, arginfo_myext_compress)
        ZEND_FE(myext_decompress, arginfo_myext_decompress)
        ZEND_FE_END
    };

In your main extension file, include the generated header and use the ``ext_functions`` table::

    #include "myext_arginfo.h"

    zend_module_entry myext_module_entry = {
        STANDARD_MODULE_HEADER,
        "myext",
        ext_functions,
        /* ... */
        STANDARD_MODULE_PROPERTIES
    };

Understanding the generated arginfo macros
-------------------------------------------

The ``ZEND_BEGIN_ARG_*`` family of macros declares the ``zend_internal_arg_info`` array for one function.
The first element of this array is special: rather than describing a parameter, it carries the return type
and the number of required arguments.

**Choosing the right opener macro**

.. list-table::
    :header-rows: 1

    * - Return type
      - Macro to use
    * - ``void``
      - ``ZEND_BEGIN_ARG_INFO_EX(name, 0, return_ref, req_args)``
    * - Single primitive (e.g. ``IS_LONG``)
      - ``ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(name, return_ref, req_args, type_code, allow_null)``
    * - Primitive bitmask (e.g. ``string|false``)
      - ``ZEND_BEGIN_ARG_WITH_RETURN_TYPE_MASK_EX(name, return_ref, req_args, type_mask)``
    * - Object / class
      - ``ZEND_BEGIN_ARG_WITH_RETURN_OBJ_INFO_EX(name, return_ref, req_args, class_name, allow_null)``
    * - Object + primitives (e.g. ``Foo|false``)
      - ``ZEND_BEGIN_ARG_WITH_RETURN_OBJ_TYPE_MASK_EX(name, return_ref, req, class, type_mask)``

For interface/abstract methods whose return types are "tentative" (declared but not yet enforced for
covariance purposes), use the ``_WITH_TENTATIVE_RETURN_*`` variants.

**Per-parameter macros**

.. list-table::
    :header-rows: 1

    * - Parameter type
      - Macro
    * - No type hint
      - ``ZEND_ARG_INFO(pass_by_ref, name)``
    * - No type, with default
      - ``ZEND_ARG_INFO_WITH_DEFAULT_VALUE(pass_by_ref, name, "default")``
    * - Single primitive
      - ``ZEND_ARG_TYPE_INFO(pass_by_ref, name, IS_LONG, allow_null)``
    * - Single primitive, with default
      - ``ZEND_ARG_TYPE_INFO_WITH_DEFAULT_VALUE(pass_by_ref, name, IS_LONG, 0, "42")``
    * - Primitive bitmask
      - ``ZEND_ARG_TYPE_MASK(pass_by_ref, name, MAY_BE_LONG|MAY_BE_NULL, "null")``
    * - Object / class
      - ``ZEND_ARG_OBJ_INFO(pass_by_ref, name, ClassName, allow_null)``
    * - Object + primitives
      - ``ZEND_ARG_OBJ_TYPE_MASK(pass_by_ref, name, ClassName, MAY_BE_FALSE, "null")``
    * - Variadic, no type
      - ``ZEND_ARG_VARIADIC_INFO(pass_by_ref, name)``

Declaring classes, interfaces, and enums
-----------------------------------------

Stub files can also declare classes, interfaces, and enums. The ``/** @generate-class-entries */`` doc
comment instructs ``gen_stub.php`` to generate a ``register_class_*()`` function::

    <?php

    /** @generate-class-entries */

    class MyExtException extends RuntimeException {
        public function __construct(
            string $message = "",
            int $code = 0,
            ?Throwable $previous = null
        ) {}
    }

    interface Compressible {
        public function compress(int $level = -1): string;
    }

The generated header will include::

    static zend_class_entry *register_class_MyExtException(
        zend_class_entry *class_entry_RuntimeException);

    static zend_class_entry *register_class_Compressible(void);

In your MINIT, call these functions to actually register the classes::

    PHP_MINIT_FUNCTION(myext)
    {
        zend_class_entry *ce = register_class_MyExtException(
            zend_ce_runtime_exception);
        /* save ce if needed */

        register_class_Compressible();

        return SUCCESS;
    }

Declaring constants
--------------------

Constants in stub files use ``UNKNOWN`` as a placeholder value. The engine cannot infer the value from
a C ``#define``, so you still register constants in MINIT as usual, but the stub declares their names
and types for reflection::

    <?php

    /** @generate-class-entries */

    /* Module-level constants */
    const MYEXT_VERSION = UNKNOWN;
    const MYEXT_FLAG_FAST = UNKNOWN;

``gen_stub.php`` generates a ``register_myext_symbols()`` function that you call from MINIT::

    PHP_MINIT_FUNCTION(myext)
    {
        register_myext_symbols(module_number);
        /* ... */
        return SUCCESS;
    }

The generated registration function uses ``REGISTER_LONG_CONSTANT`` and similar macros, but with the
actual value set to ``MYEXT_VERSION`` -- the C preprocessor symbol of the same name. So you must ensure
that a C macro of the same name is defined before the generated header is included.

Readonly properties
--------------------

.. versionadded:: PHP 8.1

PHP 8.1 readonly properties can be declared in stub files using the ``readonly`` keyword::

    class MyValue {
        public readonly int $value;
        public function __construct(int $value) {}
    }

The generated ``register_class_MyValue()`` function will use ``ZEND_ACC_READONLY`` when declaring the
property with ``zend_declare_property``.

Migrating from PHP 7 hand-written arginfo
------------------------------------------

If you have an existing PHP 7 extension with hand-written arginfo, here is the migration path:

1. Create a ``.stub.php`` file that describes your functions in PHP syntax.
2. Run ``gen_stub.php`` to generate the ``*_arginfo.h`` file.
3. Replace your hand-written arginfo with ``#include "myext_arginfo.h"``.
4. Replace your ``zend_function_entry myext_functions[]`` table with the generated ``ext_functions[]``.
5. If you use named arguments in any of your functions, ensure the parameter names in the stub match
   the names you want to expose to PHP code.

The most common issues during migration are:

* **String/false return types**: These must use ``ZEND_BEGIN_ARG_WITH_RETURN_TYPE_MASK_EX`` with
  ``MAY_BE_STRING|MAY_BE_FALSE``, not the old ``ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX`` with
  ``IS_STRING, 1``.

* **Parameter names**: PHP 7 arginfo often used ``""`` (empty string) as the parameter name.
  Named arguments require real names. The stub file always uses the real names.

* **Return by reference**: The ``return_ref`` argument to ``ZEND_BEGIN_ARG_*`` macros controls whether
  the function can return by reference. Most functions pass ``0`` here.
