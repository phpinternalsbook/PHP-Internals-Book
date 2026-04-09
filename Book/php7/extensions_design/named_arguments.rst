Named arguments
===============

.. versionadded:: PHP 8.0

   Named arguments were introduced in PHP 8.0 and are not available in PHP 7.

PHP 8.0 introduced named arguments, which allow callers to pass function arguments by name rather than by
position. For example::

    // PHP userland
    array_slice(array: $a, offset: 2, length: 3, preserve_keys: true);

This chapter covers how named arguments work internally, and what extension authors must do to support them.

How named arguments work at the call site
------------------------------------------

At the call site, the PHP compiler handles named arguments in two different ways depending on whether the
call target is known at compile time:

**Statically known target (most common)**
    When calling a named function or a method via a class literal (``Foo::bar()``), the compiler resolves
    the argument names against the target function's arginfo at compile time. It reorders the arguments
    into positional order before emitting the call opcodes. From the callee's perspective, the arguments
    arrive in the expected positional slots and there is nothing special to handle.

**Dynamically dispatched target**
    When calling through a variable (``$fn()``), ``call_user_func()``, ``Closure::call()``, and similar
    dynamic dispatch paths, the VM resolves named arguments at runtime using
    ``zend_handle_named_arg()``. Arguments that match declared parameter names by name are placed in the
    correct positional slots. Arguments that do not match any parameter name (overflow named args for a
    variadic function) are stored in ``execute_data->extra_named_params``.

The ``extra_named_params`` hash table
---------------------------------------

When named arguments overflow (because the function is variadic and the named argument does not correspond
to any fixed parameter), they are stored in the ``extra_named_params`` field of ``zend_execute_data``::

    struct _zend_execute_data {
        /* ... other fields ... */
        zend_array *extra_named_params;
    };

This field is ``NULL`` for most calls. The ``ZEND_CALL_HAS_EXTRA_NAMED_PARAMS`` flag (bit 27 of the call
info word) is set when extra named params are present.

After the function returns, the engine frees this hash table automatically.

What extension functions must do
----------------------------------

**Non-variadic functions**: Nothing special. The ZPP system (``ZEND_PARSE_PARAMETERS_START`` and
``Z_PARAM_*``) handles positionally-resolved named arguments transparently. You do not need to change
anything in the function body.

**Variadic functions**: If your variadic function accepts named arguments, use
``Z_PARAM_VARIADIC_WITH_NAMED`` to capture both the positional variadic arguments and the overflow
named params::

    PHP_FUNCTION(my_variadic)
    {
        zval     *args       = NULL;
        uint32_t  args_count = 0;
        HashTable *named     = NULL;

        ZEND_PARSE_PARAMETERS_START(0, -1)
            Z_PARAM_VARIADIC_WITH_NAMED(args, args_count, named)
        ZEND_PARSE_PARAMETERS_END();

        /* args[0..args_count-1] hold the positional variadic arguments */

        if (named) {
            zend_string *key;
            zval *val;
            ZEND_HASH_FOREACH_STR_KEY_VAL(named, key, val) {
                /* key: argument name, val: its value */
            } ZEND_HASH_FOREACH_END();
        }
    }

The ``named`` pointer may be ``NULL`` if no named arguments were passed. Do not free it -- the engine
owns this hash table.

Requiring proper parameter names in arginfo
--------------------------------------------

For named arguments to work, each parameter in the function's arginfo must have a real name. The
:doc:`stub file system <stub_files>` always generates correct parameter names from the stub.

With hand-written arginfo, using an empty string ``""`` as a parameter name silently disables named
argument support for that parameter::

    /* Broken: empty parameter names prevent named argument use */
    ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_bad, 0, 2, IS_LONG, 0)
        ZEND_ARG_TYPE_INFO(0, "", IS_LONG, 0)  /* name "" breaks named args */
        ZEND_ARG_TYPE_INFO(0, "", IS_LONG, 0)
    ZEND_END_ARG_INFO()

    /* Correct: real names */
    ZEND_BEGIN_ARG_WITH_RETURN_TYPE_INFO_EX(arginfo_good, 0, 2, IS_LONG, 0)
        ZEND_ARG_TYPE_INFO(0, a, IS_LONG, 0)
        ZEND_ARG_TYPE_INFO(0, b, IS_LONG, 0)
    ZEND_END_ARG_INFO()

Disabling named arguments
--------------------------

Some functions cannot meaningfully support named arguments -- for example, functions that use ``func_get_args()``
internally, or functions where argument names are not stable parts of the public API. To opt out of named
argument support for a function, use the ``ZEND_ACC_NO_NAMED_ARGS`` flag::

    static const zend_function_entry myext_functions[] = {
        ZEND_RAW_FENTRY("myext_internal", zif_myext_internal, arginfo_myext_internal,
            ZEND_ACC_NO_NAMED_ARGS, NULL, NULL)
        ZEND_FE_END
    };

When ``ZEND_ACC_NO_NAMED_ARGS`` is set, calling the function with named arguments throws a ``TypeError``.

Calling PHP functions with named arguments from C
--------------------------------------------------

To call a PHP function from C code and pass named arguments, populate the ``named_params`` field of
``zend_fcall_info``::

    zend_fcall_info fci = {0};
    zend_fcall_info_cache fcc = {0};

    /* Build the named args HashTable */
    HashTable *named = emalloc(sizeof(HashTable));
    zend_hash_init(named, 2, NULL, ZVAL_PTR_DTOR, 0);

    zval val;
    ZVAL_LONG(&val, 42);
    zend_hash_str_add(named, "level", sizeof("level") - 1, &val);

    fci.size = sizeof(fci);
    fci.named_params = named;
    ZVAL_UNDEF(&fci.function_name); /* set appropriately */
    fci.retval = &retval;
    fci.param_count = 0;
    fci.params = NULL;

    zend_call_function(&fci, &fcc);

    zend_hash_destroy(named);
    efree(named);

Alternatively, use ``zend_call_known_function()`` which accepts a ``named_params`` pointer directly::

    zend_call_known_function(
        fn,           /* zend_function* */
        object,       /* zend_object* or NULL */
        called_scope, /* zend_class_entry* or NULL */
        &retval,      /* zval* return value */
        0,            /* param_count */
        NULL,         /* params */
        named         /* named_params HashTable* */
    );

Pass ``NULL`` for ``named_params`` when there are no named arguments.

Named arguments and reflection
--------------------------------

From a reflection perspective, the names declared in arginfo are what PHP's ``ReflectionParameter::getName()``
returns. Using the stub file system ensures these names match the stub exactly, which is what callers see
when they look up parameter names for a call like::

    $ref = new ReflectionFunction('myext_add');
    foreach ($ref->getParameters() as $p) {
        echo $p->getName() . "\n";  // prints the stub parameter names
    }
