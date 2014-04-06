Function registration
=====================

In this section we'll take a closer look at how PHP represents functions internally, how they can be registered
from an extension and how information about arguments is specified.

Internal representation
-----------------------

PHP represents all types of functions (this includes ordinary functions as well as methods and closures) using the
``zend_function`` union, which is defined as follows::

    typedef union _zend_function {
        zend_uchar type;

        struct {
            zend_uchar type;
            const char *function_name;
            zend_class_entry *scope;
            zend_uint fn_flags;
            union _zend_function *prototype;
            zend_uint num_args;
            zend_uint required_num_args;
            zend_arg_info *arg_info;
        } common;

        zend_op_array op_array;
        zend_internal_function internal_function;
    } zend_function;

This union has four members: ``op_array`` represents a userland function, ``internal_function`` an internal function
and ``common`` contains all attributes that are shared between those two types. The ``type`` member is effectively the
same as ``common.type`` and is only present to simplify usage.

Lets start by taking a look at the common attributes: The first one, the ``type``, specifies whether this is an internal
(``ZEND_INTERNAL_FUNCTION``) or a userland (``ZEND_USER_FUNCTION``) function. There are a number of other, more obscure
function types, e.g. ``ZEND_EVAL_CODE``, which is used to represent the code passed to the ``eval()`` language
construct. As you can see the "function" part of ``zend_function`` shouldn't be taken particularly strictly, as this
structure represents not only functions and methods, but also whole scripts and eval code.

The role of the ``function_name`` member should be obvious. ``fn_flags`` is a bitmask of ``ZEND_ACC_*`` function flags.
Examples of such flags are ``ZEND_ACC_PUBLIC`` (and all other method modifiers), ``ZEND_ACC_DEPRECATED`` and
``ZEND_ACC_RETURN_REFERENCE``. However there is a rather large number of other flags, many of them relating to various
implementation details that are not relevant at this point.

For methods ``scope`` specifies the class the method was declared in. If inheritance is used ``prototype`` contains the
parent method.

The remaining members deal with function parameters (or arguments, both terms are used interchangeably by PHP):
``arg_info`` is an array of ``zend_arg_info`` structures, which specify information like the argument name, whether it
is passed by reference, what typehint it uses, etc. ``num_args`` is the number of arguments declared in this array.
Note that this number says nothing about the number of arguments the function expects: You may be able to pass both more
and less arguments than ``num_args`` to the function.

A minimum number of arguments can however be specified via ``required_num_args``. Note that this field is to the most
part only informational, it is not enforced. The function implementation itself must ensure that the number of provided
arguments is correct. The only role ``required_num_args`` has (apart from being available via the Reflection API) is to
ensure that the Liskov Substitution Principle is not violated during inheritance: It is not possible to increase the
number of required parameters when extending a method.

None of the ``common`` members specify the actual implementation of the function. This is what the specialized
``zend_internal_function`` and ``zend_op_array`` structures deal with. ``zend_internal_function`` is defined as folows::

    typedef struct _zend_internal_function {
        /* Common elements */
        zend_uchar type;
        const char *function_name;
        zend_class_entry *scope;
        zend_uint fn_flags;
        union _zend_function *prototype;
        zend_uint num_args;
        zend_uint required_num_args;
        zend_arg_info *arg_info;
        /* END of common elements */

        void (*handler)(INTERNAL_FUNCTION_PARAMETERS);
        struct _zend_module_entry *module;
    } zend_internal_function;

In addition to the common attributes already listed in ``zend_function``, this structure contains a ``handler``, which
is a function pointer to the actual implementation of the function. This is what PHP invokes when the function is
called. The parameters of this function are hidden behind the ``INTERNAL_FUNCTION_PARAMETERS`` macro, which we'll
inspect a bit later. Additionally internal functions store the ``module`` (extension) that defined it.

We won't look at the ``zend_op_array`` structure at this point - it is much more complex and not very relevant to
most extensions. You will only need to deal with this structure if you're working on the language compiler or executor
(or some other low-level component).

Functions are stored in a "function table", which is a dictionary of lowercased function names to ``zend_function``
structures. For global functions that function table is ``EG(function_table)``, for methods there are separate function
tables in each class.

Registering internal functions
------------------------------

Luckily we don't have to manually create ``zend_function`` structures and insert them into an appropriate table. Instead
we only have to specify the simpler ``zend_function_entry`` structure and the rest happens automatically::

    typedef struct _zend_function_entry {
        const char *fname;
        void (*handler)(INTERNAL_FUNCTION_PARAMETERS);
        const struct _zend_arg_info *arg_info;
        zend_uint num_args;
        zend_uint flags;
    } zend_function_entry;

This structure only contains the function name, the function handler, the array of arginfo structures (and the size of
that array) as well as function flags. Multiple functions are defined in a NULL terminated array::

    const zend_function_entry ext_functions[] = {
        { "function1", handler1, NULL, 0 /* no arginfo */, 0 /* no flags */ },
        { "function2", handler2, NULL, 0 /* no arginfo */, 0 /* no flags */ },
        /* ... more functions ... */
        { NULL, NULL, NULL, 0, 0 } /* NULL termination */
    };

These function entries then need to be registered in some way. For non-methods this is done via an entry in the
``zend_module_entry`` structure you're already familiar with::

    zend_module_entry gmp_module_entry = {
        STANDARD_MODULE_HEADER,
        "extname",
        ext_functions,
        /* ... */
    };

When the module is loaded, the ``zend_register_functions()`` function will be called with ``ext_functions``. This
function is responsible for converting the function entries into actual functions and registering them in the function
table.

``PHP_FE`` and related macros
-----------------------------

However, manually typing out the ``zend_function_entry`` structures is not encouraged. It is both cumbersome and
non-portable, as the structure may change over time. Instead you should make use of macros provided for this purpose.
All macros that will be introduced in the following exist in two variants: One starting with ``ZEND``, the other
starting with ``PHP``. Both do exactly the same thing, but by convention the ``PHP`` variants are used in PHP extensions
and the ``ZEND`` variants in Zend extensions (or other low-level code). The following examples will make use of ``PHP``.

First of all, instead of terminating with a rather ugly ``{ NULL, NULL, NULL, 0, 0 }`` line, we can use ``PHP_FE_END``
instead. The manual function entries can be replaced with ``PHP_NAMED_FE()``, resulting in the following code::

    void handler1(INTERNAL_FUNCTION_PARAMETERS) {
        /* function1 implementation */
    }

    void handler2(INTERNAL_FUNCTION_PARAMETERS) {
        /* function2 implementation */
    }

    const zend_function_entry ext_functions[] = {
        PHP_NAMED_FE(function1, handler1, NULL /* no arginfo */)
        PHP_NAMED_FE(function2, handler2, NULL /* no arginfo */)
        /* ... more functions ... */
        PHP_FE_END
    };

The ``PHP_NAMED_FE()`` macro does three things: Firstly, the function name is now provided as a plain label and
automatically converted to a string. Secondly, the size of the arginfo array no longer needs to be explicitly specified,
it will be inferred. Lastly, the function flags are set to ``0``, which is what you usually want.

This last example already includes the function handlers, which right now can have some arbitrary name. In this case
``handler1`` belongs to ``function1``, but we could just as well associate a handler ``foo`` to a function ``xyz``. To
avoid such haphazard naming PHP uses a naming convention where the handler for a function ``func_name`` is called
``zif_func_name``. The "zif" prefix stands for "Zend internal function".

This naming convention is supported by the two macros ``PHP_FUNCTION()`` (for handler declarations) and ``PHP_FE()``
(for function entries)::

    PHP_FUNCTION(function1) {
        /* function1 implementation */
    }

    PHP_FUNCTION(function2) {
        /* function2 implementation */
    }

    const zend_function_entry ext_functions[] = {
        PHP_FE(function1, NULL /* no arginfo */)
        PHP_FE(function2, NULL /* no arginfo */)
        /* ... more functions ... */
        PHP_FE_END
    };

``PHP_FUNCTION(function1)`` here resolves to ``void zif_function1(INTERNAL_FUNCTION_PARAMETERS)``. The corresponding
``PHP_FE()`` entry then makes use of this function.

A handler can be reused by multiple functions, which effectively makes them aliases. For example if ``function1`` and
``function2`` should have the same implementation, the function registration could look like this::

    PHP_FUNCTION(function1) {
        /* function1 and function2 implementation */
    }

    const zend_function_entry ext_functions[] = {
        PHP_FE(function1, NULL /* no arginfo */)
        PHP_NAMED_FE(function2, PHP_FN(function1), NULL /* no arginfo */)
        PHP_FE_END
    };

``PHP_FN()`` is a macro that provides the standardized handler name for a function, i.e. ``PHP_FN(function1)``
evaluates to ``zif_function1`` (to avoid hardcoding this convention all over the place). As this kind of aliasing is
common a specialized macro is provided for it as well::

    const zend_function_entry ext_functions[] = {
        PHP_FE(function1, NULL /* no arginfo */)
        PHP_FALIAS(function2, function1, NULL /* no arginfo */)
        PHP_FE_END
    };

``PHP_DEP_FE()`` and ``PHP_DEP_FALIAS()`` can be used to declare deprecated functions (i.e. add
``ZEND_ACC_DEPRECATED`` to the function flags). E.g. the previous example, but with a deprecated ``function2`` alias::

    const zend_function_entry ext_functions[] = {
        PHP_FE(function1, NULL /* no arginfo */)
        PHP_DEP_FALIAS(function2, function1, NULL /* no arginfo */)
        PHP_FE_END
    };

Lastly, all of these also exist in a ``ZEND_NS`` variant (this time only ``ZEND``, no ``PHP``), which accept the
namespace of the function as the first argument. The previous example, but placing the functions in the
``some\vendor\ns`` namespace::

    PHP_FUNCTION(function1) {
        /* function1 and function2 implementation */
    }

    const zend_function_entry ext_functions[] = {
        ZEND_NS_FE("some\\vendor\\ns", function1, NULL /* no arginfo */)
        ZEND_NS_DEP_FALIAS("some\\vendor\\ns", function2, function1, NULL /* no arginfo */)
        PHP_FE_END
    };

Note that the handler name (and as such the ``PHP_FUNCTION()`` declaration) does not include the namespace prefix, it
only uses the shortname of the function (a backslash in a C function name would be rather problematic).

Defining argument information
-----------------------------

When registering a function it is possible to specify additional information about its arguments using the ``arg_info``
argument of the individual macros. In all of the previous examples we didn't make use of this possibility and passed
``NULL`` instead.

Argument information is specified using an array of ``zend_arg_info`` structs, which are defined as follows::

    typedef struct _zend_arg_info {
        const char *name;
        zend_uint name_len;
        const char *class_name;
        zend_uint class_name_len;
        zend_uchar type_hint;
        zend_uchar pass_by_reference;
        zend_bool allow_null;
        zend_bool is_variadic;
    } zend_arg_info;

The ``name`` member obviously specifies the name of the argument. ``type_hint`` can be (currently) one of ``0`` (no
typehint), ``IS_ARRAY``, ``IS_CALLABLE`` or ``IS_OBJECT``. For ``IS_OBJECT`` the ``class_name`` member additionally
specifies the expected class/interface of the object. ``allow_null`` determines whether the argument accepts ``null``
in addition to the hinted type.

``pass_by_reference`` specifies whether the argument is passed by reference. In addition to the values ``0`` (or
``ZEND_SEND_BY_VAL`` if you want to be explicit) and ``1`` (or ``ZEND_SEND_BY_REF``) it also accepts
``ZEND_SEND_PREFER_REF``. This is an argument sending mode which is available exclusively to internal functions and not
exposed to userland PHP: It will send the argument by-reference if possible and by-value otherwise. E.g. a call to
``func($var)`` would send ``$var`` by reference, but ``func(42)`` would also be allowed and send ``42`` by value.

The ``is_variadic`` option is available as of PHP 5.6 and can only be be used on the last argument. It explicitly
specifies that the function takes a variable amount of arguments. The typehint and ``pass_by_reference`` value for this
argument will apply to all arguments passed afterwards as well.

Note that the arginfo does *not* contain a default value or similar. Internal functions do not have a generic concept
of a default value. Instead defaults are handled in the implementation of the function itself.

Arginfo structures are defined using the ``ZEND_ARG_INFO()`` family of macros. Here's a simple example for the
``substr`` function::

    /* substr($string, $start [, $length]) */

    ZEND_BEGIN_ARG_INFO_EX(arginfo_substr, 0, 0, 2)
        ZEND_ARG_INFO(0, string)
        ZEND_ARG_INFO(0, start)
        ZEND_ARG_INFO(0, length)
    ZEND_END_ARG_INFO()

    const zend_function_entry ext_functions[] = {
        PHP_FE(strpos, arginfo_strpos)
        /* more functions */
        PHP_FE_END
    };

The structure is started using ``ZEND_BEGIN_ARG_INFO_EX()`` and ended with ``ZEND_END_ARG_INFO()``. The starting macro
takes four arguments of which only the first and last are usually relevant: The first one is the name of the structure
(``arginfo_func_name`` is a good choice) and the last one the number of required arguments for the function. Remember
that no minimal argument number is actually enforced, this number is only used for Reflection and LSP checks during
inheritance. The second argument of ``ZEND_BEGIN_ARG_INFO_EX()`` is unused as of PHP 5.6 (its meaning in earlier
versions will be discussed later) and the third argument specifies whether the function returns by reference.

The individual arguments are defined using ``ZEND_ARG_INFO()``, which takes ``pass_by_reference`` followed by the
argument name. ``pass_by_reference`` will usually be zero, sometimes ``1`` and rarely ``ZEND_SEND_PREFER_REF``.

If all arguments of a function are required you can use ``ZEND_BEGIN_ARG_INFO()`` (without the ``_EX``) instead::

    /* usort(&$array, $value_compare_func) */

    ZEND_BEGIN_ARG_INFO(arginfo_usort, 0)
        ZEND_ARG_INFO(1, array)              /* 1 means by-reference pass */
        ZEND_ARG_INFO(0, value_compare_func)
    ZEND_END_ARG_INFO()

Here the required argument number will be set to ``2``. The additional ``0`` argument to ``ZEND_BEGIN_ARG_INFO()`` is
the same as the second argument to ``ZEND_BEGIN_ARG_INFO_EX()``, i.e. no longer used.

There are three further macros for specifying type hints. ``ZEND_ARG_OBJ_INFO()`` is used for class/interface
typenhints::

    /* iterator_to_array(Traversable $iterator [, $use_keys]) */

    ZEND_BEGIN_ARG_INFO_EX(arginfo_iterator_to_array, 0, 0, 1)
        ZEND_ARG_OBJ_INFO(0, iterator, Traversable, 0)
        ZEND_ARG_INFO(0, use_keys)
    ZEND_END_ARG_INFO();

The last ``0`` argument of this macro is whether ``null`` is accepted next to the class type. The other two macros are
``ZEND_ARG_ARRAY_INFO()`` for arrays and ``ZEND_ARG_TYPE_INFO()`` for typehints that don't have a specialized macro
(i.e. callables). Thus a more precise arginfo structure for ``usort`` could be written as follows::

    /* usort(array &$array, callable $value_compare_func) */

    ZEND_BEGIN_ARG_INFO(arginfo_usort, 0)
        ZEND_ARG_ARRAY_INFO(1, array, 0)
        ZEND_ARG_TYPE_INFO(0, value_compare_func, IS_CALLABLE, 0)
    ZEND_END_ARG_INFO()

The last ``0`` for both macros once again sets ``allow_null=0``.

If you look through the arginfo structures for core functions, you'll find that they do not specify a typehint in most
cases, even if they could. Quite commonly ``ZEND_ARG_INFO()`` is followed by a typehinted variant that is commented out.
The reason is that nearly all internal functions verify the argument type in the implementation, while fetching the
parameters. As such a typehint would only result in a duplicate type check (and callability checks for example are
rather expensive.) However, it can still make sense to provide the typehint in arginfo, as it is also exposed via the
Reflection API.

The last arginfo macro is ``ZEND_ARG_VARIADIC_INFO()`` and is only available in PHP 5.6 and newer. Here's a sample
usage for the ``sscanf()`` function::

    /* sscanf($str, $format, &...$vars) */

    ZEND_BEGIN_ARG_INFO_EX(arginfo_sscanf, 0, 0, 2)
        ZEND_ARG_INFO(0, str)
        ZEND_ARG_INFO(0, format)
        ZEND_ARG_VARIADIC_INFO(1, vars)
    ZEND_END_ARG_INFO()

The use of the ``VARIADIC`` macro specifies that this function takes a variable number of arguments. The send type ``1``
(i.e. by-reference) will be applied to all arguments starting with the third one. In earlier versions of PHP (before
5.6) the same behavior can be accomplished with the following definition::

    ZEND_BEGIN_ARG_INFO_EX(arginfo_sscanf, 1, 0, 2)
        ZEND_ARG_INFO(0, str)
        ZEND_ARG_INFO(0, format)
        ZEND_ARG_INFO(1, var)
        ZEND_ARG_INFO(1, ...)
    ZEND_END_ARG_INFO()

Note that the second parameter of ``ZEND_BEGIN_ARG_INFO_EX()`` is now ``1``. This indicates that all arguments that are
not specified in the arginfo should be passed by reference (and as such does the same as the ``VARIADIC`` declaration).
The name of the last argument does not need to be ``...``, however this was the usual convention to mark up variadic
functions in older PHP versions.