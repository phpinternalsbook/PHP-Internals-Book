Observer API
============

.. versionadded:: PHP 8.0

   The Observer API was introduced in PHP 8.0. In PHP 7, the only way to observe every function call
   was to overwrite global function pointers such as ``zend_execute_ex`` and ``zend_execute_internal``,
   which was fragile and incompatible with other extensions.

Before PHP 8, extensions that needed to observe every function call (for profilers, debuggers, APM agents,
and similar tools) had no official hook. The common approach was to overwrite global function pointers such
as ``zend_execute_ex``, ``zend_execute_internal``, and ``zend_error_cb``, or to replace individual opcode
handlers. These techniques were fragile and incompatible with each other and with the JIT compiler.

PHP 8.0 introduced the **Observer API** as an officially supported, composable mechanism for observing
function execution and other engine events. Multiple extensions can register observers simultaneously
without interfering with each other, and the observer hooks are JIT-compatible.

The Observer API is defined in ``Zend/zend_observer.h``.

The function call observer
---------------------------

The core of the Observer API is a per-function ``begin``/``end`` handler pair. The typical workflow is:

1. Register a factory function (``zend_observer_fcall_init``) during ``MINIT``.
2. The engine calls your factory the first time each function runs (lazily).
3. Your factory inspects the function and returns either ``{NULL, NULL}`` (opt out) or a
   ``{begin, end}`` handler pair.
4. The engine caches the handlers and calls them at the start and end of every subsequent call.

**Handler types**::

    typedef void (*zend_observer_fcall_begin_handler)(zend_execute_data *execute_data);
    typedef void (*zend_observer_fcall_end_handler)(zend_execute_data *execute_data,
                                                     zval *retval);

    typedef struct _zend_observer_fcall_handlers {
        zend_observer_fcall_begin_handler begin;
        zend_observer_fcall_end_handler   end;
    } zend_observer_fcall_handlers;

**Factory type**::

    typedef zend_observer_fcall_handlers (*zend_observer_fcall_init)(
        zend_execute_data *execute_data);

**Registration** (must be called during ``MINIT``)::

    ZEND_API void zend_observer_fcall_register(zend_observer_fcall_init init_fn);

A minimal profiling extension
-------------------------------

Here is a complete example of a profiling extension that records wall-clock time for every function call::

    #include "zend_observer.h"
    #include <time.h>

    /* Per-call state stored on the VM stack */
    typedef struct {
        struct timespec start;
    } my_call_state;

    static void my_begin(zend_execute_data *execute_data)
    {
        zend_function *fn = execute_data->func;
        /* Allocate state on the VM stack if needed; for simplicity,
         * use a static here (not thread-safe). */
        clock_gettime(CLOCK_MONOTONIC, &((my_call_state *)
            ZEND_OBSERVER_DATA(execute_data, zend_observer_fcall_op_array_extension)
        )->start);
    }

    static void my_end(zend_execute_data *execute_data, zval *retval)
    {
        struct timespec end;
        clock_gettime(CLOCK_MONOTONIC, &end);

        zend_function *fn = execute_data->func;
        if (fn->common.function_name) {
            /* compute elapsed and record ... */
        }
    }

    static zend_observer_fcall_handlers my_init(zend_execute_data *execute_data)
    {
        zend_function *fn = execute_data->func;

        /* Skip functions without a name (top-level script) */
        if (!fn->common.function_name) {
            return (zend_observer_fcall_handlers){NULL, NULL};
        }

        return (zend_observer_fcall_handlers){my_begin, my_end};
    }

    PHP_MINIT_FUNCTION(myprofiler)
    {
        zend_observer_fcall_register(my_init);
        return SUCCESS;
    }

The ``my_init`` function is called **once per function**, the first time that function executes. Returning
``{NULL, NULL}`` means "do not observe this function". The choice is cached permanently (until the next
request or opcache reset), so the factory is not called again for the same function.

Observing internal functions
-----------------------------

By default in PHP 8.0, the observer factory was only called for user-defined (PHP) functions. PHP 8.2
changed this: ``zend_observer_fcall_init`` handlers are now also called for internal (C) functions. If
your factory should only observe PHP functions, check ``fn->type``::

    static zend_observer_fcall_handlers my_init(zend_execute_data *execute_data)
    {
        zend_function *fn = execute_data->func;

        if (fn->type != ZEND_USER_FUNCTION) {
            return (zend_observer_fcall_handlers){NULL, NULL};
        }

        /* ... */
    }

Runtime handler management
---------------------------

In addition to the factory registration, the Observer API allows adding and removing handlers per-function
at runtime::

    /* Add a begin handler for a specific function */
    ZEND_API void zend_observer_add_begin_handler(
        zend_function *function,
        zend_observer_fcall_begin_handler begin);

    /* Remove a begin handler (returns true if removed, false if not found).
     * The next parameter receives the handler that should be called if removal
     * happened during observer execution (PHP 8.4+). */
    ZEND_API bool zend_observer_remove_begin_handler(
        zend_function *function,
        zend_observer_fcall_begin_handler begin,
        zend_observer_fcall_begin_handler *next);

    /* Same for end handlers */
    ZEND_API void zend_observer_add_end_handler(
        zend_function *function,
        zend_observer_fcall_end_handler end);
    ZEND_API bool zend_observer_remove_end_handler(
        zend_function *function,
        zend_observer_fcall_end_handler end,
        zend_observer_fcall_end_handler *next);

Only one begin handler and one end handler can be active simultaneously for a given function. Remove the
existing handler before adding a replacement.

Other observable events
------------------------

The Observer API covers several engine events beyond function calls:

**Function declaration** (compile time)::

    typedef void (*zend_observer_function_declared_cb)(
        zend_op_array *op_array, zend_string *name);

    ZEND_API void zend_observer_function_declared_register(
        zend_observer_function_declared_cb cb);

Called when a PHP function or method is defined (i.e., when its containing file is compiled).

**Class linking**::

    typedef void (*zend_observer_class_linked_cb)(
        zend_class_entry *ce, zend_string *name);

    ZEND_API void zend_observer_class_linked_register(
        zend_observer_class_linked_cb cb);

Called when a class is linked (its parent class, interfaces, and traits are resolved). This is the
appropriate place to act on class-level attributes.

**Error notification**::

    typedef void (*zend_observer_error_cb)(
        int type, zend_string *error_filename,
        uint32_t error_lineno, zend_string *message);

    ZEND_API void zend_observer_error_register(zend_observer_error_cb callback);

This is the replacement for the old pattern of overwriting ``zend_error_cb``. Use this instead. Multiple
extensions can each register their own error callback without conflicting.

**Fiber lifecycle** (PHP 8.1+)::

    typedef void (*zend_observer_fiber_init_handler)(zend_fiber_context *initializing);
    typedef void (*zend_observer_fiber_switch_handler)(zend_fiber_context *from,
                                                       zend_fiber_context *to);
    typedef void (*zend_observer_fiber_destroy_handler)(zend_fiber_context *destroying);

    ZEND_API void zend_observer_fiber_init_register(
        zend_observer_fiber_init_handler handler);
    ZEND_API void zend_observer_fiber_switch_register(
        zend_observer_fiber_switch_handler handler);
    ZEND_API void zend_observer_fiber_destroy_register(
        zend_observer_fiber_destroy_handler handler);

These callbacks are called when a fiber is created, when execution switches between fibers (or between
a fiber and the main thread), and when a fiber is destroyed. This is essential for profilers and APM tools
that track per-fiber execution time or context.

Checking if the observer system is active
------------------------------------------

The observer infrastructure has a small overhead even when no observers are registered, because the engine
must check whether to call observer hooks. You can test whether any observers are active::

    if (ZEND_OBSERVER_ENABLED) {
        /* At least one observer factory has been registered */
    }

``ZEND_OBSERVER_ENABLED`` is defined as::

    #define ZEND_OBSERVER_ENABLED \
        (zend_observer_fcall_op_array_extension != -1)

This is a fast global check. It is set to ``-1`` (disabled) at startup and changed to a valid extension
slot handle the first time a factory is registered.

The ``ZEND_CALL_OBSERVED`` flag
---------------------------------

When an observer begin handler is active for a function, the engine sets the
``ZEND_CALL_OBSERVED`` flag (bit 28) in the call info word of the current ``zend_execute_data``. This
enables the fast path for the end handler: the engine knows it must call the end handler without
checking the handler table again.

If your observer needs to know whether the current call is observed from within the ``begin`` handler, you
can check::

    if (ZEND_CALL_INFO(execute_data) & ZEND_CALL_OBSERVED) {
        /* We are inside an observed call */
    }

Compatibility with the JIT
----------------------------

The Observer API is fully compatible with the JIT compiler. The JIT respects observer hooks and does not
optimise away observed function calls. This is one of the key advantages of the Observer API over the
old approach of overwriting ``zend_execute_ex`` -- the latter caused the JIT to disable itself entirely.

If your extension only uses the Observer API (and not ``zend_execute_ex`` or custom opcode handlers), the
JIT will remain active and your extension will benefit from JIT-compiled PHP code alongside its observing.
