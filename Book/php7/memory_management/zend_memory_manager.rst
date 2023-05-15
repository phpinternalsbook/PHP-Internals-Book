.. _zend_mm:

Zend Memory Manager
===================

Zend Memory Manager, often abbreviated as *ZendMM* or *ZMM*, is a C layer that aims to provide abilities to allocate
and release dynamic **request-bound** memory.

Note the "request-bound" in the above sentence.

ZendMM is not just a classical layer over libc's dynamic memory allocator, mainly represented by the couple API calls
``malloc()/free()``. ZendMM is about request-bound memory that PHP must allocate while treating a request.

The two main kind of dynamic memory pools in PHP
************************************************

PHP is a share-nothing architecture. Well, not at 100%. Let us explain.

.. note:: You may need to read :doc:`the PHP lifecycle chapter <../extensions_design/php_lifecycle>` before continuing
          here, you'll get additional information about the different steps and cycles that can be drawn from PHP
          lifetime.

PHP can treat several hundreds or thousands of requests into the same process. By default, PHP will forget anything it
knows of the current request, when that later finishes.

"Forgetting" things translates to freeing any dynamic buffer that got allocated while treating a request. That means
that when in the process of treating a request, one must not allocate dynamic memory using traditional libc calls.
Doing that is perfectly valid, but you give a chance to forget to free such a buffer.

ZendMM comes with an API that substitute to libc's dynamic allocator, by copying its API. When in the process of
treating a request, the programmer must use that API instead of libc's allocator.

For example, when PHP treats a request, it will parse PHP files. Those ones will lead to functions and classes
declarations, for example. When the compiler comes to compile the PHP files, it will allocate some dynamic memory to
store classes and functions it discovers. But, at the end of the request, PHP will forget about those latter. By
default, PHP forgets *a very huge number* of information from one request to another.

There exists however some pretty rare information you need to persist across several requests. But that's uncommon.

What could be kept unchanged through requests ? What we call **persistent** objects. Once more let us insist : those
are rare cases. For example, the current PHP executable path won't change from requests to requests. That latter
information is allocated permanently, that means it is allocated with a traditional libc's ``malloc()`` call.

What else? Some strings. For example, the *"_SERVER"* string will be reused from request to request, as every request
will create the ``$_SERVER`` PHP array. So the *"_SERVER"* string itself can be permanently allocated, because it will
be allocated once.

What you must remember:

* There exists two kinds of dynamic memory allocations while programming PHP Core or extensions:
    * Request-bound dynamic allocations.
    * Permanent dynamic allocations.

* Request-bound dynamic memory allocations
    * Must only be performed when PHP is treating a request (not before, nor after).
    * Should only be performed using the ZendMM dynamic memory allocation API.
    * Are very common in extensions design, basically 95% of your dynamic allocations will be request-bound.
    * Are tracked by ZendMM, and you'll be informed about leaking.

* Permanent dynamic memory allocations
    * Should not be performed while PHP is treating a request (not forbidden, but a bad idea).
    * Are not tracked by ZendMM, and you won't be informed about leaking.
    * Should be pretty rare in an extension.

Also, keep in mind that all PHP source code has been based on such a memory level. Thus, many internal structures get
allocated using the Zend Memory Manager. Most of them got a "persistent" API call, which when used, lead to
traditional libc allocation.

Here is a request-bound allocated :doc:`zend_string <../internal_types/strings/zend_strings>`::

    zend_string *foo = zend_string_init("foo", strlen("foo"), 0);

And here is the persistent allocated one::

    zend_string *foo = zend_string_init("foo", strlen("foo"), 1);

Same for :doc:`HashTable <../internal_types/hashtables>`. Request-bound allocated one::

    zend_array ar;
    zend_hash_init(&ar, 8, NULL, NULL, 0);

Persistent allocated one::

    zend_array ar;
    zend_hash_init(&ar, 8, NULL, NULL, 1);

It is always the same in all the different Zend APIs. Usually, it is whether a *"0"* to pass as last parameter to mean
"I want this structure to be allocated using ZendMM, so request-bound", or *"1"* meaning "I want this structure to get
allocated bypassing ZendMM and using a traditional libc's ``malloc()`` call".

Obviously, those structures provide an API that remembers how it did allocate the structure, to use the right
deallocation function when destroyed. Hence in such a code::

    zend_string_release(foo);
    zend_hash_destroy(&ar);

The API knows whether those structures were allocated using request-bound allocation, or permanent one, and in the
first case will use ``efree()`` to release it, and in the second case libc's ``free()``.

Zend Memory Manager API
***********************

The API is located into
`Zend/zend_alloc.h <https://github.com/php/php-src/blob/c3b910370c5c92007c3e3579024490345cb7f9a7/Zend/zend_alloc.h>`_

The API calls are mainly C macros and not functions, so get prepared if you debug them and want to look at how they
work. Those calls copy libc's calls, they usually add an "e" in the function name; So you should not be lost, and there
is not many things to detail about the API.

Basically what you'll use most are ``emalloc(size_t)`` and ``efree(void *)``.

You are also provided with ``ecalloc(size_t nmemb, size_t size)`` that allocates ``nmemb`` of individual size ``size``,
and zeroes the area. If you are a strong C programmer with experience, you should know that whenever possible, it is
better to use ``ecalloc()`` over ``emalloc()`` as ``ecalloc()`` will zero out the memory area which could help a lot in
pointer bug detection. Remember that ``emalloc()`` works basically like the libc ``malloc()``: it will look for a big
enough area in different pools, and return you the best fit. So you may be given a recycled pointer which points to
garbage.

Then comes ``safe_emalloc(size_t nmemb, size_t size, size_t offset)``, which is an ``emalloc(size * nmemb + offset)``
but that does check against overflows for you. You should use this API call if the numbers you must provide come from an
untrusted source, like the userland.

About string facilities, ``estrdup(char *)`` and ``estrndup(char *, size_t len)`` allow to duplicate strings or binary
strings.

Whatever happens, pointers returned by ZendMM must be freed using ZendMM, aka ``efree()`` call and
**not libc's free()**.

.. note:: A note on persistent allocations. Persistent allocations stay alive between requests. You traditionnaly use
          the common libc ``malloc/free`` to perform that, but ZendMM has got some shortcuts to libc allocator : the
          "persistent" API. This API starts by the *"p"* letter and let you choose between ZendMM alloc, or persistent
          alloc. Hence a ``pemalloc(size_t, 1)`` is nothing more than a ``malloc()``, a ``pefree(void *, 1)`` is a
          ``free()`` and a ``pestrdup(void *, 1)`` is a ``strdup()``. Just to say.

Zend Memory Manager debugging shields
*************************************

ZendMM provides the following abilities:

* Memory consumption management.
* Memory leak tracking and automatic-free.
* Speed up in allocations by pre-allocating well-known-sized buffers and keeping a warm cache on free

Memory consumption management
-----------------------------

ZendMM is the layer behind the PHP userland "memory_limit" feature. Every single byte allocated using the ZendMM layer
is counted and added. When the INI's *memory_limit* is reached, you know what happens.
That also mean that any allocation you perform via ZendMM is reflected in the ``memory_get_usage()`` call from PHP
userland.

As an extension developer, this is a good thing, because it helps mastering the PHP process' heap size.

If a memory limit error is launched, the engine will bail out from the current code position to a catch block, and will
terminate smoothly. But there is no chance it goes back to the location in your code where the limit blew up.
You must be prepared to that.

That means that in theory, ZendMM cannot return a NULL pointer to you. If the allocation fails from the OS, or if the
allocation generates a memory limit error, the code will run into a catch block and won't return to you allocation call.

If for any reason you need to bypass that protection, you must then use a traditional libc call, like ``malloc()``.
Take care however and know what you do. It may happen that you need to allocate lots of memory and could blow up the PHP
*memory_limit* if using ZendMM. Thus use another allocator (like libc) but take care: your extension will grow the
current process heap size. That cannot be seen using ``memory_get_usage()`` in PHP, but by analyzing the current heap
with the OS facilities (like */proc/{pid}/maps*)

.. note:: If you need to fully disable ZendMM, you can launch PHP with the ``USE_ZEND_ALLOC=0`` env var. This way, every
          call to the ZendMM API (like ``emalloc()``) will be directed to a libc call, and ZendMM will be disabled.
          This is especially useful when :doc:`debugging memory <./memory_debugging>`.

Memory leak tracking
--------------------

Remember the main ZendMM rules: it starts when a request starts, it then expects you call its API when in need of
dynamic memory as you are treating a request. When the current request ends, ZendMM shuts down.

By shutting down, it will browse every of its active pointer, and if using
:doc:`a debug build<../build_system/building_php>` of PHP, it will warn you about memory leaking.

Let's be clear here: if at the end of the current request ZendMM finds some active memory blocks, that means those are
leaking. There should not be any active memory block living onto ZendMM heap at the end of the request, as anyone who
allocated some should have freed them.

If you forget to free blocks, they will all get displayed on *stderr*. This process of memory leak reporting only works
in the following conditions:

* You are using :doc:`a debug build<../build_system/building_php>` of PHP
* You have *report_memleaks=On* in php.ini (default)

Here is an example of a simple leak into an extension::

    PHP_RINIT_FUNCTION(example)
    {
        void *foo = emalloc(128);
    }

When launching PHP with that extension activated, on a debug build, that generates on stderr:

.. code-block:: text

    [Fri Jun 9 16:04:59 2017]  Script:  '/tmp/foobar.php'
    /path/to/extension/file.c(123) : Freeing 0x00007fffeee65000 (128 bytes), script=/tmp/foobar.php
    === Total 1 memory leaks detected ===

Those lines are generated when the Zend Memory Manager shuts down, that is at the end of each treated request.

Beware however:

* Obviously ZendMM doesn't know anything about persistent allocations, or allocations that were performed in another way
  than using it. Hence, ZendMM can only warn you about allocations it is aware of, every traditional libc allocation
  won't be reported in here, f.e.
* If PHP shuts down in an incorrect maner (what we call an unclean shutdown), ZendMM will report tons of leaks. This is
  because when incorrectly shutdown, the engine uses a
  `longjmp() <http://man7.org/linux/man-pages/man3/longjmp.3.html>`_ call to a catch block, preventing every code that
  cleans memory to fire-in. Thus, many leaks get reported. This happens especially after a call to PHP's exit()/die(),
  or if a fatal error gets triggered in some critical parts of PHP.
* If you use a non-debug build of PHP, nothing shows on *stderr*, ZendMM is dumb but will still clean any allocated
  request-bound buffer that's not been explicitly freed by the programmer

What you must remember is that ZendMM leak tracking is a nice bonus tool to have, but it does not replace a
:doc:`true C memory debugger <./memory_debugging>`.

Lifecycle
*********

PHP will call the ``start_memory_manager()`` function during it's startup phase, specifically when the PHP process is
started (for instance, when the PHP-FPM service is started, or when a PHP CLI script is run). This will allocate the
heap and the first chunk.

During a request the ZendMM will allocate chunks as needed.

On every request shutdown (during the ``RSHUTDOWN`` phase), the ZendEngine will call the ``shutdown_memory_manager()``
function (which calls the ``zend_mm_shutdown()`` function) with the boolean argument ``full`` set to ``false``. This
will cleanup for the next request, but not do a full shutdown of the memory manager. For example it will not free the
heap and keep the average amount of chunks used during the current request alive in the ``cached_chunks`` pointer on the
heap to be reused in the next request.

In the module shutdown phase (``MSHUTDOWN``) the ZendEngine will call the ``shutdown_memory_manager()`` function (which
calls the ``zend_mm_shutdown()`` function) with the boolean argument ``full`` set to ``true``, which will trigger a full
shutdown and free all cached chunks as well as the heap itself.

ZendMM internal design
**********************

The root of the ZendMM is the ``_zend_mm_heap`` struct (as defined in `Zend/zend_alloc.c
<https://github.com/php/php-src/blob/c3b910370c5c92007c3e3579024490345cb7f9a7/Zend/zend_alloc.c#L239>`__) which will be
created for every request during request init and stored in the ``alloc_globals->mm_heap``. This heap also comes with
the first chunk that is allocated with it. Chunks are then subdivided into pages. Smaller allocations are stored in bins
which may fit into one page but some also span multiple pages.

Interal memory organisation
---------------------------

Heap
++++

The heap, as defined in the struct ``_zend_mm_heap``, holds links to chunks (``main_chunk`` and ``cached_chunks``, for
small and large allocations), ``huge_list`` for huge allocations (>= 2MB) and to bins (for small allocations) in
``free_slots[BIN]``. After initialisation only the ``main_chunk`` exists and none or some ``cached_chunks``.

Chunks
++++++

Each chunk is 2 MB in size and consists of 512 pages. The first page of every chunk is reserved for the chunk header as
defined in the struct ``_zend_mm_chunk`` (as defined in `Zend/zend_alloc.c
<https://github.com/php/php-src/blob/c3b910370c5c92007c3e3579024490345cb7f9a7/Zend/zend_alloc.c#L286>`__). Chunks are
organised in a linked list with ``prev`` and ``next`` pointers.

Each chunk holds a bit mask in ``free_map`` (512 bits) where a single bit indicates if a page is in use or free.
Information on what is in a page is stored in ``map`` which is an array of 512 32 bit integers. Each of those integers
is used as a bitmap and holds the meta information about that page.

Pages
+++++

A page is 4096 bytes in size and can either hold a bin (for small allocations) or be part of a large allocation. What is
in it can be found in the map of the chunk the page belongs to.

Bins
++++

Small allocations are grouped together in bins. Bin sizes are predefined and come in 30 different sizes (8, 16, 24, 32,
... 3072 bytes). A bin holds same sized values and is linked from the heap directly.

A bin can consist of multiple pages. Example: There exists a bin that holds elements ranging from 257 bytes to 320 bytes
which occupies 5 pages, and therefore has room for 64 (derived from 4096*5/320) elements of that size.

Allocation categories
---------------------

Small allocations
+++++++++++++++++

Allocations less or equal than 3072 bytes are organised in bins.

If a bin is already initialised, the ``free_slot`` pointer on the ``zend_mm_heap`` struct is the address to be used
(this address will be returned by the call to ``emalloc()`` and will be incremented to point to the next free slot, see
implementation in ``zend_mm_alloc_small``).

If the bin for this specific size is not initialised already, it will be created in the ``zend_mm_alloc_small_slow``
function and a pointer to the first element of the bin is returned.

Large allocations
+++++++++++++++++

Allocations bigger than 3072 bytes, but small enough to fit in a chunk (2 MB chunk size - 4096 bytes chunk header (first
page) makes 2093056 bytes) are directly stored in the pages. The first page will be marked ``LRUN`` in the map of the
chunk and also hold the number of allocated pages.

Huge allocations
++++++++++++++++

If an allocation is larger than the chunk size minus one page (2 MB chunk size - 4096 bytes chunk header (first page)
makes 2093056 bytes) the memory is allocated using ``mmap()`` and put on the ``huge_list`` linked list on the heap.

Hooking into the ZendMM
***********************

You can call the ``zend_mm_set_custom_handlers()`` function and give it pointers to your ``malloc``, ``free`` and
``realloc`` handlers as well as your custom heap. You may as well use the existing heap you can fetch via
``zend_mm_get_heap()``.

.. code-block:: c

    void* my_malloc(size_t len) {
        return malloc(len);
    }

    void my_free(void* ptr) {
        free(ptr);
    }

    void* my_realloc(void* ptr, size_t len) {
        return realloc(ptr, len);
    }

    PHP_MINIT_FUNCTION(my_extension) {
        zend_mm_set_custom_handlers(
            zend_mm_get_heap(),
            my_malloc,
            my_free,
            my_realloc
        );
        return SUCCESS;
    }

While this is the only possible way to extend the ZendMM, this also alters the behaviour in two ways. As soon as a
custom memory manager is installed:

* ZendMM will not cleanup chunks anymore during ``zend_mm_shutdown()`` (which is called during PHP request shutdown),
  leaving you with a memory leak if your custom handlers just forward calls to the ZendMM internal functions
* ZendMM's garbage collector implemented in ``zend_mm_gc()`` will not be doing anything in case a custom memory handler
  is installed

Common errors and mistakes
**************************

Here are the most common errors while using ZendMM, and what you should do about them.

1. Usage of ZendMM as you are not treating a request.

Get infos about
:doc:`the PHP lifecycle <../extensions_design/php_lifecycle>` to know in your extensions when you are treating a
request, and when not. If you use ZendMM out of the scope of a request (like in ``MINIT()``), the allocation will be
silently cleared by ZendMM before treating the first request, and you'll probably use-after-free : simply don't.

2. Buffer overflow and underflows.

Use a :doc:`memory debugger <memory_debugging>`. If you write below or past a memory area returned by ZendMM, you will
overwrite crucial ZendMM structures and trigger a crash. It may happen that the *"zend_mm_heap corrupted"* message gets
display in case ZendMM was able to detect the mess for you. The stack trace will show a crash from some code, to some
ZendMM code. ZendMM code does not crash itself. If you get crashed in the middle of ZendMM code, that highly probably
means you messed up with a pointer somewhere. Kick in your favorite memory debugger and look for the guilty part and
fix it.

3. Mix API calls

If you allocate a ZendMM pointer (``emalloc()`` f.e) and free it using libc (``free()``), or the opposite scenario:
you will crash. Be rigorous. Also if you pass to ZendMM's ``efree()`` any pointer it doesn't know about: you will crash.
