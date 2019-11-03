Hooks provided by PHP
=====================

PHP and the Zend Engine provide many different hooks for extensions that allow
extension developers to control the PHP runtime in ways that are not available
from PHP userland.

This chapter will show various hooks and common use-cases for hooking into them
from an extension.

The general pattern for hooking into PHP functionality are extensions
overwriting function pointers that the PHP core provides. The extension
function then often performs their own work and calls the original PHP core
function. Using this pattern different extensions can overwrite the same hook
without causing conflicts.

Hooking into the execution of functions
***************************************

The execution of userland and internal functions are handled by two functions
within the Zend engine that you can replace with your own implementations.
The primary use-case for extensions to overwrite this hook is generic
function-level profiling, debugging and aspect oriented programming.

The hooks are defined in ``Zend/zend_execute.h``::

    ZEND_API extern void (*zend_execute_ex)(zend_execute_data *execute_data);
    ZEND_API extern void (*zend_execute_internal)(zend_execute_data *execute_data, zval *return_value);

If you want to overwrite these function pointers, then you must do this in
MINIT, because other decisions inside the Zend Engine are made early based on
the fact if the pointers are overwritten or not.

The usual pattern for overwriting is this::

    static void (*original_zend_execute_ex) (zend_execute_data *execute_data);
    static void (*original_zend_execute_internal) (zend_execute_data *execute_data, zval *return_value);
    void my_execute_internal(zend_execute_data *execute_data, zval *return_value);
    void my_execute_ex (zend_execute_data *execute_data);

    PHP_MINIT_FUNCTION(my_extension)
    {
        REGISTER_INI_ENTRIES();

        original_zend_execute_internal = zend_execute_internal;
        zend_execute_internal = my_execute_internal;

        original_zend_execute_ex = zend_execute_ex;
        zend_execute_ex = my_execute_ex;

        return SUCCESS;
    }

    PHP_MSHUTDOWN_FUNCTION(my_extension)
    {
        zend_execute_internal = original_zend_execute_internal;
        zend_execute_ex = original_zend_execute_ex;

        return SUCCESS;
    }

One downside of overwriting ``zend_execute_ex`` is that it changes the Zend
Virtual Machine runtime behavior to use recursion instead of handling calls
without leaving the interpreter loop. In addition a PHP engine without
overwritten ``zend_execute_ex`` can also generate more optimized function call
opcodes.

These hooks are very performance sensitive depending on the complexity of code
that wraps the original functions.

Overwriting an Internal Function
********************************

While overwriting the execute hooks an extension can record **every** function
call, you can also overwrite individual function pointers of userland, core and
extension functions (and methods). This has much better performance
characteristics if an extension only needs access to specific internal function
calls.::

    #if PHP_VERSION_ID < 70200
    typedef void (*zif_handler)(INTERNAL_FUNCTION_PARAMETERS);
    #endif
    zif_handler original_handler_var_dump;

    ZEND_NAMED_FUNCTION(my_overwrite_var_dump)
    {
        // if we want to call the original function
        original_handler_var_dump(INTERNAL_FUNCTION_PARAM_PASSTHRU);
    }

    PHP_MINIT_FUNCTION(my_extension)
    {
        zend_function *original;

        original = zend_hash_str_find_ptr(EG(function_table), "var_dump", sizeof("var_dump")-1);

        if (original != NULL) {
            original_handler_var_dump = original->internal_function.handler;
            original->internal_function.handler = my_overwrite_var_dump;
        }
    }

When overwriting a class method, the function table can be found on the
``zend_class_entry``.::

    zend_class_entry *ce = zend_hash_str_find_ptr(CG(class_table), "PDO", sizeof("PDO")-1);
    if (ce != NULL) {
        original = zend_hash_str_find_ptr(&ce->function_table, "exec", sizeof("exec")-1);

        if (original != NULL) {
            original_handler_pdo_exec = original->internal_function.handler;
            original->internal_function.handler = my_overwrite_pdo_exec;
        }
    }

Modifying the Abstract Syntax Tree (AST)
****************************************

When PHP 7 compiles PHP code it converts it into an abstract syntax tree (AST)
before finally generating Opcodes that are persisted in Opcache. The
``zend_ast_process hook`` is called for every compiled script and allows you to
modify the AST after it is parsed and created.

This is one of the most complicated hooks to use, because it requires perfect
understanding of the AST possibilities. Creating an invalid AST here can cause
weird behavior or crashes.

It is best to look at example extensions that use this hook:

- `Google Stackdriver PHP Debugger Extension
  <https://github.com/GoogleCloudPlatform/stackdriver-debugger-php-extension/blob/master/stackdriver_debugger_ast.c>`_
- Based on Stackdriver this `Proof of Concept Tracer with AST <https://github.com/beberlei/php-ast-tracer-poc/blob/master/astracer.c>`_

Hooking into Script/File Compilation
************************************

Whenever a user script calls ``include``/``require`` or their counterparts
``include_once``/``require_once`` PHP core calls the function at the pointer
``zend_compile_file`` to handle this request. The argument is a file handle
and the result is a ``zend_op_array``.::

    zend_op_array *my_extension_compile_file(zend_file_handle *file_handle, int type);

There are two extensions in PHP core that implement this hook: dtrace and
opcache.

- If you start the PHP script with the environment variable ``USE_ZEND_DTRACE``
  and compiled PHP with dtrace support, then ``dtrace_compile_file`` is used
  from ``Zend/zend_dtrace.c``.

- Opcache stores op arrays in shared memory for better performance, so that
  whenever a script is compiled its final op array is served from a cache and
  not re-compiled. You can find this implementation in
  ``ext/opcache/ZendAccelerator.c``.

- The default implementation called ``compile_file`` is part of the scanner
  code in ``Zend/zend_language_scanner.l``.

Use cases for implementing this hook are Opcode Accelerating, PHP code
encrypting/decrypting, debugging or profiling.

You can replace this hook whenever you want in the execution of a PHP process
and all PHP scripts compiled after the replacement will be handled by your
implementation of the hook.

It is very important to always call the original function pointer, otherwise
PHP cannot compile scripts anymore and Opcache will not work anymore.

The extension overwriting order here is also important as you need to be aware
whether you want to register your hook before or after Opcache, because Opcache
does not call the original function pointer if it finds an opcode array entry
in its shared memory cache. Opcache registers their hook as a post startup
hook, which runs after the minit phase for extensions, so by default your hook
will not be called anymore when the script gets cached.

Notification when Error Handler is called
*****************************************

Similar to the PHP userland ``set_error_handler()`` function, an extension can
register itself as error handler by implementing the ``zend_error_cb`` hook.::

    ZEND_API void (*zend_error_cb)(int type, const char *error_filename, const uint32_t error_lineno, const char *format, va_list args);

The ``type`` variable corresponds to the ``E_*`` error constants that are also
available in PHP userland.

The relationship between PHP core and userland error handlers is complex:

1. If no userland error handler is registered then ``zend_error_cb`` is always
   called.
2. If userland error handler is registered, then for all errors of ``E_ERROR``,
   ``E_PARSE``, ``E_CORE_ERROR``, ``E_CORE_WARNING``, ``E_COMPILE_ERROR`` and
   ``E_COMPILE_WARNING`` the ``zend_error_cb`` hook is always called.
3. For all other errors, the ``zend_error_cb`` is only called if the userland
   handler fails or returns ``false``.

In addition Xdebug overwrites the error handler in a way that does not call
previously registered internal handlers, because of its complex own
implementation.

As such overwriting this hook is not very reliable.

Again overwriting should be done in a way that respects the original handler
unless you want to completely replace it::

    void (*original_zend_error_cb)(int type, const char *error_filename, const uint error_lineno, const char *format, va_list args);

    void my_error_cb(int type, const char *error_filename, const uint error_lineno, const char *format, va_list args)
    {
        // my special error handling here

        original_zend_error_cb(type, error_filename, error_lineno, format, args);
    }

    PHP_MINIT_FUNCTION(my_extension)
    {
        original_zend_error_cb = zend_error_cb;
        zend_error_cb = my_error_cb;

        RETURN SUCCESS;
    }

    PHP_MSHUTDOWN(my_extension)
    {
        zend_error_cb = original_zend_error_cb;
    }

This hook is mainly used to implement central exception tracking for Exception
Tracking or Application Performance Management software.

Notification when Exception is thrown
*************************************

Whenever PHP Core or userland code throws an exception the
``zend_throw_exception_hook`` is called with the exception as argument.

This hooks' signature is fairly simple::

    void my_throw_exception_hook(zval *exception)
    {
        if (original_zend_throw_exception_hook != NULL) {
            original_zend_throw_exception_hook(exception);
        }
    }

This hook has no default implementation and points to ``NULL`` if not
overwritten by an extension.

::

    static void (*original_zend_throw_exception_hook)(zval *ex);
    void my_throw_exception_hook(zval *exception);

    PHP_MINIT_FUNCTION(my_extension)
    {
        original_zend_throw_exception_hook = zend_throw_exception_hook;
        zend_throw_exception_hook = my_throw_exception_hook;

        return SUCCESS;
    }

If you implement this hook be aware that this hook is called regardless of
whether the exception is caught or not. It can still be useful to temporarily
store the exception here and then combine this with an implementation of the
Error Handler hook to check if the exception was uncaught and caused the script
to halt.

Use-cases to implement this hook include debugging, logging and exception
tracking.

Hooking into eval()
*******************

PHPs ``eval`` is not an internal function but a special language construct. As
such you cannot hook into it through ``zend_execute_internal`` or by
overwriting its function pointer.

Use cases for hooking into eval are not that many, you can use it for profiling
or for security purposes. If you change its behavior be aware that other extensions
may need eval. One example is Xdebug that uses it to execute breakpoint conditions.

::

    extern ZEND_API zend_op_array *(*zend_compile_string)(zval *source_string, char *filename);

Hooking into the Garbage Collector
**********************************

PHPs Garbage Collector can be triggered explicitly when ``gc_collect_cycles()``
is called or implicitly by the engine itself when the number of collectable
objects reaches a certain threshold.

To allow understanding of how the garbage collector works or to profile its
performance, you can overwrite the function pointer hook that performs the
garbage collection operation. Theoretically you can implement your own garbage
collection algorithm here, but given other changes to the engine would probably
be necessary this probably is not really feasible.

::

    int (*original_gc_collect_cycles)(void);

    int my_gc_collect_cycles(void)
    {
        original_gc_collect_cycles();
    }

    PHP_MINIT_FUNCTION(my_extension)
    {
        original_gc_collect_cycles = gc_collect_cycles;
        gc_collect_cycles = my_gc_collect_cycles;

        return SUCCESS;
    }

Overwrite Interrupt Handler
***************************

The interrupt handler is called once when the executor global
``EG(vm_interrupt)`` is set to 1. This is checked at regular checkpoints during
the execution of userland code. The engine uses this hook to implement the PHP
execution timeout via a signal handler that sets the interrupt to 1 after the
timeout duration is reached.

This can be helpful to defer signal handling to a later stage of the runtime
execution, when it is safer to clean up or to implement your own timeout
handling. By setting this hook you cannot accidentally disable the timeout check
of PHP, because it has customized handling that has higher priority than any
overwrite of ``zend_interrupt_function``.

::

    ZEND_API void (*original_interrupt_function)(zend_execute_data *execute_data);

    void my_interrupt_function(zend_execute_data *execute_data)
    {
        if (original_interrupt_function != NULL) {
            original_interrupt_function(execute_data);
        }
    }

    PHP_MINIT_FUNCTION(my_extension)
    {
        original_interrupt_function = zend_interrupt_function;
        zend_interrupt_function = my_interrupt_function;

        return SUCCESS;
    }

Replacing Opcode Handlers
*************************

TODO
