JIT compiler
============

.. versionadded:: PHP 8.0

   The JIT compiler was introduced in PHP 8.0 as part of the opcache extension. It is not present in
   PHP 7.

PHP 8.0 introduced a JIT (Just-In-Time) compiler, integrated as part of the opcache extension. The JIT
converts PHP opcodes into native machine code at runtime, bypassing the Zend VM interpreter for hot code
paths. For CPU-bound workloads, the JIT can provide significant performance improvements.

The JIT is not a standalone extension -- it is embedded in ``ext/opcache`` and requires opcache to be
enabled. It is inactive unless explicitly configured with a non-zero ``opcache.jit_buffer_size`` and
an appropriate ``opcache.jit`` setting.

Architecture overview
---------------------

The JIT compilation pipeline is::

    PHP source → Zend opcodes
                     ↓
              opcache Optimizer (CFG, SSA, type inference)
                     ↓
              zend_jit_op_array() / zend_jit_script()
                     ↓
              IR framework (SCCP, GCM, reg-alloc, codegen)
                     ↓
              Native machine code in shared memory buffer

The optimizer performs static analysis -- building a control flow graph (CFG), constructing SSA form,
and running type inference. The JIT uses these results to emit specialized native code. Higher optimization
levels perform more extensive analysis, including inter-procedural analysis across entire scripts.

The JIT is built on an embedded version of the **IR framework** (a lightweight JIT compilation framework)
from `github.com/dstogov/ir <https://github.com/dstogov/ir>`_. The IR framework handles scheduling,
register allocation, and code generation for the supported architectures: x86_64, i386, and AArch64.

JIT modes
----------

The ``opcache.jit`` setting accepts either a named alias or a 4-digit number ``ABCD``.

Named aliases:

.. list-table::
    :header-rows: 1

    * - Value
      - Mode
      - Description
    * - ``disable``
      - Disabled
      - JIT infrastructure is not loaded. Cannot be re-enabled at runtime.
    * - ``off`` / ``0`` / ``false``
      - Off
      - Infrastructure loaded but not compiling.
    * - ``tracing`` / ``on`` / ``1`` / ``true``
      - Tracing JIT (default)
      - Compiles hot traces after a threshold number of executions.
    * - ``function``
      - Function JIT
      - Compiles entire functions at opcache load time.

The **tracing JIT** is the default and is recommended for most workloads. It records execution traces
when a loop or function becomes hot (exceeds the configured counter threshold), then compiles those
traces to native code. It performs well on dynamic code and adapts to actual runtime types.

The **function JIT** compiles entire functions ahead of time at script load. It uses more memory but
avoids the overhead of trace recording.

The 4-digit number format
--------------------------

For fine-grained control, use a 4-digit number ``ABCD``:

.. list-table::
    :header-rows: 1
    :widths: 10 20 70

    * - Digit
      - Position
      - Meaning
    * - A
      - thousands
      - AVX usage: ``0``=disabled, ``1``=use AVX if available
    * - B
      - hundreds
      - Register allocation: ``0``=none, ``1``=local LSRA, ``2``=global LSRA
    * - C
      - tens
      - Trigger (when to compile; see ``ZEND_JIT_ON_*`` constants)
    * - D
      - units
      - Optimization level (see ``ZEND_JIT_LEVEL_*`` constants)

The trigger values (digit C):

.. list-table::
    :header-rows: 1

    * - Value
      - Constant
      - Meaning
    * - 0
      - ``ZEND_JIT_ON_SCRIPT_LOAD``
      - Compile everything at opcache load time (function JIT)
    * - 1
      - ``ZEND_JIT_ON_FIRST_EXEC``
      - Compile on first execution of the function
    * - 2
      - ``ZEND_JIT_ON_PROF_REQUEST``
      - Compile most-called functions at the start of the first request
    * - 3
      - ``ZEND_JIT_ON_HOT_COUNTERS``
      - Compile after N function calls or loop iterations
    * - 4
      - ``ZEND_JIT_ON_DOC_COMMENT``
      - Compile functions with a ``@jit`` docblock annotation
    * - 5
      - ``ZEND_JIT_ON_HOT_TRACE``
      - Tracing JIT: record and compile after N executions

The optimization levels (digit D):

.. list-table::
    :header-rows: 1

    * - Value
      - Constant
      - Description
    * - 0
      - ``ZEND_JIT_LEVEL_NONE``
      - No JIT
    * - 1
      - ``ZEND_JIT_LEVEL_MINIMAL``
      - Subroutine threading (replace VM dispatch with direct calls)
    * - 2
      - ``ZEND_JIT_LEVEL_INLINE``
      - Selective inline threading
    * - 3
      - ``ZEND_JIT_LEVEL_OPT_FUNC``
      - Type-inference-based optimization per function
    * - 4
      - ``ZEND_JIT_LEVEL_OPT_FUNCS``
      - Type-inference + call-tree optimization
    * - 5
      - ``ZEND_JIT_LEVEL_OPT_SCRIPT``
      - Type-inference + inter-procedural (whole-script) optimization

For example, ``opcache.jit=1254`` means: AVX=enabled, global LSRA, trigger=HOT_COUNTERS, level=OPT_FUNCS.

Key php.ini directives
-----------------------

.. list-table::
    :header-rows: 1

    * - Directive
      - Default
      - Description
    * - ``opcache.jit``
      - ``tracing``
      - JIT mode (see above). Set to ``disable`` to prevent JIT entirely.
    * - ``opcache.jit_buffer_size``
      - ``0``
      - Shared memory buffer for compiled code. Set to e.g. ``64M`` to enable. 0 = JIT off.
    * - ``opcache.jit_debug``
      - ``0``
      - Bitmask of debug flags (disassembly, SSA dumps, perf/VTune/GDB integration).
    * - ``opcache.jit_hot_loop``
      - ``64``
      - Loop iterations before triggering trace compilation.
    * - ``opcache.jit_hot_func``
      - ``127``
      - Function calls before triggering compilation.
    * - ``opcache.jit_max_root_traces``
      - ``1024``
      - Maximum number of trace entry points.
    * - ``opcache.jit_max_side_traces``
      - ``128``
      - Maximum side traces per root trace.
    * - ``opcache.jit_max_loop_unrolls``
      - ``8``
      - Maximum loop unroll count.
    * - ``opcache.jit_max_recursive_calls``
      - ``2``
      - Inline recursion depth limit.
    * - ``opcache.jit_max_polymorphic_calls``
      - ``2``
      - Polymorphic call inline limit.

The ``jit_buffer_size`` must be non-zero to activate the JIT. The value is carved out of the opcache
shared memory segment (controlled by ``opcache.memory_consumption``). Make sure
``opcache.memory_consumption`` is large enough to accommodate both the bytecode cache and the JIT buffer.

How tracing works
------------------

In tracing mode, each opline starts with a hot counter. The counter for a back-edge (loop) or function
entry is decremented on each execution. When the counter crosses zero:

1. The VM enters **trace recording** mode for that opline.
2. Every subsequent opline executed is recorded, including observed operand types.
3. Recording stops at a trace stop reason: back-edge of a loop (``LOOP`` stop), function return
   (``RETURN`` stop), or one of many other conditions.
4. The recorded trace is handed to the IR-based compiler.
5. If compilation succeeds, the original opline handlers are patched to jump directly to the compiled
   native code on the hot path.

The trace is specialised for the observed types. If a future execution takes a different path (e.g. the
same variable is now a string instead of an integer), a **side exit** is taken back to the interpreter.
If a side exit becomes hot, a **side trace** is compiled for that branch.

The JIT and extension compatibility
--------------------------------------

Extension authors must be aware of the following JIT compatibility requirements:

**Custom opcode handlers disable the JIT**

If any extension registers a custom opcode handler via ``zend_set_user_opcode_handler()``, the JIT
disables itself entirely for that execution. The JIT cannot safely emit native code for opcodes that
have been overridden by an extension.

This affects extensions such as Xdebug (which hooks opcodes for debugging and coverage). Such extensions
are typically incompatible with the JIT, and this is expected -- the JIT disabling is intentional.

If your extension uses opcode handlers for a non-debug purpose, consider switching to the
:doc:`Observer API <../extensions_design/observer_api>`, which is JIT-compatible.

**``ZEND_EXT_API`` functions for extensions**

The JIT exports two functions specifically for use by Zend extensions:

``zend_jit_status(zval *ret)``
    Fills a hash table with JIT runtime statistics (compiled functions, trace counts, etc.). Useful for
    monitoring and diagnostics.

``zend_jit_blacklist_function(zend_op_array *op_array)``
    Permanently prevents a specific function from being JIT-compiled. Useful for debuggers and profilers
    that need to instrument a function at the bytecode level and cannot tolerate JIT interference.

**No observer interaction needed**

Extensions that only use the :doc:`Observer API <../extensions_design/observer_api>` do not need to take
any special action. The JIT respects observer hooks and does not optimise away observed calls.

Debug flags
------------

The ``opcache.jit_debug`` directive is a bitmask that controls what debugging information the JIT emits.
These flags are useful when investigating JIT behaviour or performance::

    ZEND_JIT_DEBUG_ASM         (1 << 0)  /* print disassembly of compiled code */
    ZEND_JIT_DEBUG_SSA         (1 << 1)  /* print SSA form */
    ZEND_JIT_DEBUG_REG_ALLOC   (1 << 2)  /* register allocation dump */
    ZEND_JIT_DEBUG_ASM_STUBS   (1 << 3)  /* print JIT helper stubs */
    ZEND_JIT_DEBUG_PERF        (1 << 4)  /* Linux perf map integration */
    ZEND_JIT_DEBUG_PERF_DUMP   (1 << 5)  /* perf dump file */
    ZEND_JIT_DEBUG_VTUNE       (1 << 7)  /* Intel VTune integration */
    ZEND_JIT_DEBUG_GDB         (1 << 8)  /* GDB JIT interface (gdb 'info functions') */
    ZEND_JIT_DEBUG_TRACE_START (1 << 12) /* log when trace recording starts */
    ZEND_JIT_DEBUG_TRACE_STOP  (1 << 13) /* log when recording stops and why */
    /* ... more flags for IR optimizer pass dumps ... */

To see a disassembly of all compiled code::

    opcache.jit=tracing
    opcache.jit_buffer_size=64M
    opcache.jit_debug=1

To integrate with Linux ``perf``::

    opcache.jit_debug=16   ; (1 << 4)

Then run::

    perf record php your_script.php
    perf report

Frameless function calls (PHP 8.4)
------------------------------------

.. versionadded:: PHP 8.4

PHP 8.4 introduced **frameless function calls** (``ZEND_FRAMELESS_FUNCTION``), a JIT optimization that
allows specific internal functions to be called without creating a full ``zend_execute_data`` frame on
the VM stack. The function receives its arguments directly via opcode operands.

To make an internal function eligible for frameless calls, define a frameless handler alongside the
regular handler. The handler receives arguments as individual parameters rather than via the standard
call ABI::

    ZEND_FRAMELESS_FUNCTION(strlen, 1)   /* "1" = single argument */
    {
        zval *str;
        ZEND_FLF_ARG(str, 1);            /* fetch argument 1 */

        if (Z_TYPE_P(str) != IS_STRING) {
            /* fall back to the regular handler */
            ZEND_FLF_NARROW_RETURN();
            return;
        }

        RETURN_LONG(Z_STRLEN_P(str));
    }

Frameless handlers are registered alongside the regular function in the function entry::

    ZEND_RAW_FENTRY("strlen", zif_strlen, arginfo_strlen, 0,
                    ZEND_FLF_HANDLER(strlen, 1), NULL)

The JIT emits ``FRAMELESS_ICALL_*`` opcodes for calls to frameless-capable functions when the argument
types are statically known. This eliminates the frame setup/teardown overhead for short, simple internal
functions like ``strlen``, ``count``, ``abs``, etc.

Extension authors writing performance-critical internal functions that receive a small, fixed number of
arguments may benefit from providing frameless handlers.
