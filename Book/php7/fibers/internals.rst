Fiber internals
===============

.. versionadded:: PHP 8.1

   This chapter describes PHP 8.1+ fiber internals. The fiber infrastructure does not exist in PHP 7.

This chapter covers the internal implementation of fibers. It explains the data structures, the
context-switching mechanism, and the C API available to extensions.

The two-level fiber design
---------------------------

PHP fibers are built on two layers:

* **``zend_fiber_context``** is the low-level coroutine primitive. It owns a C stack and can switch
  CPU execution to another context. It is not a PHP object. Event-loop libraries (such as Revolt) use
  ``zend_fiber_context`` directly to implement their own scheduler without the overhead of PHP objects.

* **``zend_fiber``** is the PHP ``Fiber`` class object. It wraps a ``zend_fiber_context``, owns a PHP
  VM stack, and implements the ``start()``/``resume()``/``suspend()``/``getReturn()`` interface visible
  to PHP code.

This separation means that the fiber coroutine infrastructure can be used from C without being tied to
the PHP ``Fiber`` class.

The ``zend_fiber_context`` structure
--------------------------------------

Defined in ``Zend/zend_fibers.h``::

    struct _zend_fiber_context {
        void *handle;          /* platform context handle (ucontext_t* or fcontext_t) */
        void *kind;            /* pointer identifying context type (e.g. class entry) */
        zend_fiber_coroutine function;  /* entry point coroutine function */
        zend_fiber_clean      cleanup;  /* destructor called when context is destroyed */
        zend_fiber_stack     *stack;    /* the C stack for this context */
        zend_fiber_status     status;
        zend_execute_data    *top_observed_frame; /* for stack walkers / profilers */
        void *reserved[ZEND_MAX_RESERVED_RESOURCES]; /* hook for extension data */
    };

The status values::

    ZEND_FIBER_STATUS_INIT       /* created, not yet started */
    ZEND_FIBER_STATUS_RUNNING    /* currently on-CPU */
    ZEND_FIBER_STATUS_SUSPENDED  /* suspended, can be resumed */
    ZEND_FIBER_STATUS_DEAD       /* finished or threw an unhandled exception */

The ``kind`` pointer is the distinguishing mechanism. PHP ``Fiber`` objects set ``kind`` to
``&zend_fiber_class`` (the class entry for the ``Fiber`` class). Custom contexts created by event-loop
libraries use their own pointer. This allows stack walkers and profilers to identify whether a context
belongs to a PHP fiber or a library-defined lightweight coroutine.

The ``reserved`` array is an extension hook point. Each slot is a ``void*`` that the engine initializes
to ``NULL``. Extensions can use ``zend_get_resource_handle()`` to claim a slot and then store per-context
data there.

The ``zend_fiber`` structure
-----------------------------

The PHP ``Fiber`` object wraps a ``zend_fiber_context``::

    struct _zend_fiber {
        zend_object       std;        /* MUST be first -- enables object <-> fiber casting */
        uint8_t           flags;      /* ZEND_FIBER_FLAG_* bitmask */
        zend_fiber_context context;   /* the fiber's own coroutine context */
        zend_fiber_context *caller;   /* context that resumed this fiber */
        zend_fiber_context *previous; /* previous context in the resume chain */
        zend_fcall_info       fci;
        zend_fcall_info_cache fci_cache;
        zend_execute_data    *execute_data;   /* fiber's current execute_data frame */
        zend_execute_data    *stack_bottom;   /* bottom of fiber's VM stack */
        zend_vm_stack         vm_stack;       /* fiber's own VM stack */
        zval                  result;         /* value passed between suspend/resume */
    };

Fiber flags::

    ZEND_FIBER_FLAG_THREW     = 1 << 0   /* threw an unhandled exception */
    ZEND_FIBER_FLAG_BAILOUT   = 1 << 1   /* fatal error inside the fiber */
    ZEND_FIBER_FLAG_DESTROYED = 1 << 2   /* fiber is being destroyed */

Because ``std`` is the first member, you can cast between ``zend_object*`` and ``zend_fiber*`` directly::

    zend_object *obj = /* a PHP Fiber instance */;
    zend_fiber *fiber = (zend_fiber *) obj;

VM state capture and restore
------------------------------

Each fiber maintains a completely separate PHP VM stack. When the engine switches to a fiber, it
snapshots the current VM state into a temporary struct and replaces it with the fiber's state.

The ``zend_fiber_vm_state`` struct (internal to ``zend_fibers.c``) stores::

    zend_vm_stack      vm_stack;
    zval              *vm_stack_top;
    zval              *vm_stack_end;
    size_t             vm_stack_page_size;
    zend_execute_data *current_execute_data;
    int                error_reporting;
    uint32_t           jit_trace_num;
    JMP_BUF           *bailout;
    zend_fiber        *active_fiber;

``zend_fiber_capture_vm_state()`` snapshots the current ``EG(...)`` (executor globals) into this struct.
``zend_fiber_restore_vm_state()`` writes them back. Each switch involves one capture and one restore.

Stack allocation
-----------------

Each fiber gets its own C stack. The size is configurable with the ``fiber.stack_size`` php.ini
directive. Default sizes::

    ZEND_FIBER_DEFAULT_C_STACK_SIZE = 4096 * (sizeof(void*) < 8 ? 256 : 512)
    /* = 1 MB on 32-bit, 2 MB on 64-bit */

The C stack is allocated with ``mmap`` (on Unix) or ``VirtualAlloc`` (on Windows). Guard pages
(``ZEND_FIBER_GUARD_PAGES = 1`` page) are placed at the bottom of the stack to catch overflow with a
SIGSEGV/SIGBUS before corruption occurs.

Each fiber also gets its own PHP VM stack (``ZEND_FIBER_VM_STACK_SIZE = 1024 * sizeof(zval)``), which
is separate from the C stack and used by the Zend executor for PHP function call frames.

The context switch mechanism
-----------------------------

The actual CPU context switch is performed by ``zend_fiber_switch_context()``. The implementation
supports two backends:

**Boost.Context (default on most platforms)**
    Uses hand-written assembly routines ``make_fcontext`` and ``jump_fcontext`` for maximum performance.
    Handles Intel CET (shadow stacks) on modern Linux. Supported on x86_64, i386, AArch64, and ARM.

**POSIX ``ucontext``** (fallback)
    Uses POSIX ``makecontext()`` / ``swapcontext()``. Slower due to signal mask management, but
    universally available. Used when Boost.Context is not available for the target platform.

A simplified view of ``zend_fiber_switch_context()``::

    void zend_fiber_switch_context(zend_fiber_transfer *transfer)
    {
        zend_fiber_context *from = EG(current_fiber_context);
        zend_fiber_context *to = transfer->context;
        zend_fiber_vm_state state;

        zend_observer_fiber_switch_notify(from, to); /* notify observers */

        zend_fiber_capture_vm_state(&state);         /* snapshot EG(...) */

        to->status = ZEND_FIBER_STATUS_RUNNING;
        if (from->status == ZEND_FIBER_STATUS_RUNNING)
            from->status = ZEND_FIBER_STATUS_SUSPENDED;

        transfer->context = from;                    /* tell destination who switched to it */
        EG(current_fiber_context) = to;

        /* ---- platform context switch happens here ---- */
        /* On return, another fiber has switched back to us */

        to = transfer->context;
        EG(current_fiber_context) = from;
        zend_fiber_restore_vm_state(&state);         /* restore EG(...) */

        if (to->status == ZEND_FIBER_STATUS_DEAD)
            zend_fiber_destroy_context(to);
    }

The ``zend_fiber_transfer`` struct is allocated on the C stack and passed as the communication channel
between two sides of a switch::

    typedef struct _zend_fiber_transfer {
        zend_fiber_context *context;    /* IN: context to switch TO; OUT: who switched to us */
        zval                value;      /* value passed between suspend/resume */
        uint8_t             flags;      /* ZEND_FIBER_TRANSFER_FLAG_ERROR etc. */
    } zend_fiber_transfer;

Each fiber's entry point is ``zend_fiber_trampoline()``, which receives the initial ``transfer``,
calls ``context->function(&transfer)``, marks the context dead, and performs a final switch back to
the caller.

The public C API
-----------------

**Context lifecycle**::

    /* Initialize a context: allocate stack and set up entry function.
     * kind: a unique pointer identifying this context type (e.g. your class entry).
     * coroutine: the entry function, called on first switch.
     * stack_size: 0 means use the default. */
    ZEND_API zend_result zend_fiber_init_context(
        zend_fiber_context     *context,
        void                   *kind,
        zend_fiber_coroutine    coroutine,
        size_t                  stack_size);

    /* Free the stack and clean up */
    ZEND_API void zend_fiber_destroy_context(zend_fiber_context *context);

    /* Perform the CPU + VM state switch */
    ZEND_API void zend_fiber_switch_context(zend_fiber_transfer *transfer);

**Stack introspection**::

    ZEND_API void *zend_fiber_stack_limit(zend_fiber_stack *stack);
    ZEND_API void *zend_fiber_stack_base(zend_fiber_stack *stack);

**Switch blocking** (to prevent context switches in signal handlers, destructors, etc.)::

    ZEND_API void zend_fiber_switch_block(void);
    ZEND_API void zend_fiber_switch_unblock(void);
    ZEND_API bool zend_fiber_switch_blocked(void);

**PHP-level Fiber object API**::

    ZEND_API zend_result zend_fiber_start(zend_fiber *fiber, zval *return_value);
    ZEND_API void zend_fiber_resume(zend_fiber *fiber, zval *value, zval *return_value);
    ZEND_API void zend_fiber_suspend(zend_fiber *fiber, zval *value, zval *return_value);

**Type conversions**::

    static inline zend_fiber *zend_fiber_from_context(zend_fiber_context *context);
    static inline zend_fiber_context *zend_fiber_get_context(zend_fiber *fiber);

The coroutine function signature
---------------------------------

If you create your own contexts with ``zend_fiber_init_context()``, the entry function must match::

    typedef void (*zend_fiber_coroutine)(zend_fiber_transfer *transfer);

Inside the coroutine, use the ``transfer`` to communicate with the switcher and to perform the next
context switch when you are ready to suspend::

    static void my_coroutine(zend_fiber_transfer *transfer)
    {
        /* transfer->value contains the value passed on start/resume */
        zval *received = &transfer->value;

        /* Do some work ... */

        /* Suspend: switch back to whoever started us, passing a value */
        ZVAL_LONG(&transfer->value, 42);
        zend_fiber_switch_context(transfer);

        /* Resume: we get here when someone switches back to us */
        /* transfer->value now contains the resume value */

        /* Final return: mark dead and switch back */
        /* (zend_fiber_trampoline does this automatically for Fiber objects) */
    }

Implications for extensions
-----------------------------

Extension code that runs inside a PHP function call may now execute inside a fiber. This has several
implications:

**Stack walking**: When walking the PHP call stack (e.g. for backtraces), you must account for fiber
boundaries. Use ``zend_fiber_context.top_observed_frame`` to find the top frame of a suspended fiber.

**Globals**: Each fiber has its own VM stack and ``current_execute_data``, but shares the global
executor globals (``EG(...)``). Globals such as ``EG(exception)`` are per-request, not per-fiber.

**Observers**: If your extension uses the :doc:`Observer API <../extensions_design/observer_api>`,
register fiber switch callbacks with ``zend_observer_fiber_switch_register()`` so you can correctly
attribute time and call depth to individual fibers.

**Per-fiber data**: Use the ``reserved[]`` array in ``zend_fiber_context`` to store per-context data.
Claim a slot with ``zend_get_resource_handle()`` and access it as
``EG(current_fiber_context)->reserved[slot]``.

**Switch blocking**: If your code must not be interrupted by a fiber switch (e.g. in a destructor that
manipulates global state), call ``zend_fiber_switch_block()`` before the critical section and
``zend_fiber_switch_unblock()`` after.
