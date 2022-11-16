PHP Callables
===================

Dealing with PHP functions in C requires the knowledge of the following two structures
``zend_fcall_info``/``zend_fcall_info_cache``. The first one necessarily contains the information for calling
the function, such as arguments and the return value, but may also include the actual callable.
The latter *only* contains the callable. We will use the commonly used abbreviation of FCI and FCC when talking about
``zend_fcall_info`` and ``zend_fcall_info_cache`` respectively.
You will most likely encounter those when using the ZPP ``f`` argument flag, or when you need to call a PHP function
or method from within an extension.

Structure of ``zend_fcall_info``
--------------------------------

.. warning:: The implementation of ``zend_fcall_info`` is widely different prior to PHP 7.1.0.

As of PHP 8.0.0, ``zend_fcall_info`` has the following structure:

::

    struct _zend_fcall_info {
        size_t size;
        zval function_name;
        zval *retval;
        zval *params;
        zend_object *object;
        uint32_t param_count;
        /* This hashtable can also contain positional arguments (with integer keys),
         * which will be appended to the normal params[]. This makes it easier to
         * integrate APIs like call_user_func_array(). The usual restriction that
         * there may not be position arguments after named arguments applies. */
        HashTable *named_params;
    } zend_fcall_info;


Let detail the various FCI fields:

``size``:
  Mandatory field, which is the size of an FCI structure, thus always: ``sizeof(zend_fcall_info)``
``function_name``:
  Mandatory field, the actual callable, do not be fooled by the name of this field as this is a leftover when
  PHP didn't have objects and class methods. It must be a string zval or an array following the same rules as
  callables in PHP, namely the first index is a class or instance object, and the second one is the method name.
  It can also be undefined if, and only if, an initialized FCC is provided.
``retval``:
  Mandatory field, which will contain the result of the PHP function
``param_count``:
  Mandatory field, the number of arguments that will be provided to this call to the function
``params``:
  contains positional arguments that will be provided to this call to the function.
  If ``param_count = 0``, it can be ``NULL``.
``object``:
  The object on which to call the method name stored in ``function_name``, or ``NULL`` if no objects are involved.
``named_params``:
  A HashTable containing named (or positional) arguments.

.. note:: Prior to PHP 8.0.0, the ``named_params`` field did not exist. However, a ``zend_bool no_separation;``
   field existed which specified if array arguments should be separated or not.

Structure of ``zend_fcall_info_cache``
--------------------------------------

A ``zend_fcall_info_cache`` has the following structure:

::

    typedef struct _zend_fcall_info_cache {
        zend_function *function_handler;
        zend_class_entry *calling_scope;
        zend_class_entry *called_scope;
        zend_object *object;
    } zend_fcall_info_cache;

Let detail the various FCC fields:

``function_handler``:
  The actual body of a PHP function that will be used by the VM, can be retrieved from the global function table
  or a class function table (``zend_class_entry->function_table``).
``object``:
  If the function is an object method, this field is the relevant object.
``called_scope``:
  The scope in which to call the method, generally it's ``object->ce``.
``calling_scope``:
  The scope in which this call is made, only used by the VM.

.. warning:: Prior to PHP 7.3.0 there existed an ``initialized`` field. Now an FCC is considered initialized when
  ``function_handler`` is set to a non-null pointer.

The *only* case where an FCC will be uninitialized is if the function is a trampoline, i.e. when the method
of a class does not exist but is handled by the magic methods ``__call()``/``__callStatic()``.
This is because a trampoline is freed by ZPP as it is a newly allocated ``zend_function`` struct with the
op array copied, and is freed when called. To retrieve it manually use ``zend_is_callable_ex()``.

.. warning:: It is not sufficient to just store the FCC to be able to call a user function at a later stage.
   If the callable zval from the FCI is an object (because it has an ``__invoke`` method, is a ``Closure``,
   or a trampoline) then a reference to the ``zend_object`` must also be stored, the refcount incremented,
   and released as needed. Moreover, if the callable is a trampoline the ``function_handler`` must be copied
   to be persisted between calls (see how SPL implements the storage of autoloading functions).

.. note:: In most cases an FCC does not need to be released, the exception is if the FCC may hold a trampoline
  in which case the ``void zend_release_fcall_info_cache(zend_fcall_info_cache *fcc)`` should be used to release it.
  Moreover, if a reference to the closure is kept, this must be called *prior* to freeing the closure,
  as the trampoline will partially refer to a ``zend_function *`` entry in the closure CE.

..
    This API is still being worked on and won't be usable for a year
    note:: As of PHP 8.3.0, the FCC holds a ``closure`` field and a dedicated API to handle storing userland callables.

Zend Engine API for callables
-----------------------------

The API is located at various locations in the ``Zend_API.h`` header file.
We will describe the various APIs needed to deal with callables in PHP.

First of all, to check if an FCI is initialized use the ``ZEND_FCI_INITIALIZED(fci)`` macro.

.. And, as of PHP 8.3.0, the ``ZEND_FCC_INITIALIZED(fcc)`` macro to check if an FCC is initialized.

If you have a correctly initialized and set up FCI/FCC pair for a callable you can call it directly by using the
``zend_call_function(zend_fcall_info *fci, zend_fcall_info_cache *fci_cache)`` function.

.. warning:: The ``zend_fcall_info_arg*()`` and ``zend_fcall_info_call()`` APIs should not be used.
    The ``zval *args`` parameter does *not* set the ``params`` field of the FCI directly.
    Instead it expect it to be a PHP array (IS_ARRAY zval) containing positional arguments, which will be reallocated
    into a new C array. As the ``named_params`` field accepts positional arguments, it is generally better to simply
    assign the HashTable pointer of this argument to this field.
    Moreover, as arguments to a userland call are predetermined and stack allocated it is better to assign the
    ``params`` and ``param_count`` fields directly.

..
    note:: As of PHP 8.3.0, the ``zend_call_function_with_return_value(*fci, *fcc, zval *retval)`` function has
    been added to replace the usage of ``zend_fcall_info_call(fci, fcc, retval, NULL)``.

In the more likely case where you just have a callable zval, you have the choice of a couple different options
depending on the use case.

For a one-off call the ``call_user_function(function_table, object, function_name, retval_ptr, param_count, params)``
and ``call_user_function_named(function_table, object, function_name, retval_ptr, param_count, params, named_params)``
macro-functions will do the trick.

.. note:: As of PHP 7.1.0, the ``function_table`` argument is not used and should always be ``NULL``.

The drawback of those functions is that they will verify the zval is indeed callable, and create a FCI/FCC pair on
every call. If you know you will need to call these functions multiple time it's best to create a FCI/FCC pair yourself
by using the ``zend_result zend_fcall_info_init(zval *callable, uint32_t check_flags, zend_fcall_info *fci,
zend_fcall_info_cache *fcc, zend_string **callable_name, char **error)`` function.
If this function returns ``FAILURE``, then the zval is not a proper callable.
``check_flags`` is forwarded to ``zend_is_callable_ex()``, generally you don't want to pass any modifying flags,
however ``IS_CALLABLE_SUPPRESS_DEPRECATIONS`` might be useful in certain cases.

In case you just have an FCC (or a combination of ``zend_function`` and ``zend_object``) you can use the following
functions::

    /* Call the provided zend_function with the given params.
     * If retval_ptr is NULL, the return value is discarded.
     * If object is NULL, this must be a free function or static call.
     * called_scope must be provided for instance and static method calls. */
    ZEND_API void zend_call_known_function(
		zend_function *fn, zend_object *object, zend_class_entry *called_scope, zval *retval_ptr,
		uint32_t param_count, zval *params, HashTable *named_params);

    /* Call the provided zend_function instance method on an object. */
    static zend_always_inline void zend_call_known_instance_method(
		zend_function *fn, zend_object *object, zval *retval_ptr,
		uint32_t param_count, zval *params)
    {
	    zend_call_known_function(fn, object, object->ce, retval_ptr, param_count, params, NULL);
    }

And specific parameter number variations for the latter.

.. note:: If you want to call a method on an object if it exists use the ``zend_call_method_if_exists()`` function.
