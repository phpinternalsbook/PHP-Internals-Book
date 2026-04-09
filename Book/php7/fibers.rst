Fibers
======

.. versionadded:: PHP 8.1

   Fibers were introduced in PHP 8.1 and are not available in PHP 7.

PHP 8.1 introduced fibers as a first-class language feature. A fiber is a lightweight cooperative
coroutine: it can suspend its execution at any point (calling ``Fiber::suspend()``), return a value to
the code that resumed it, and later be resumed from where it left off.

Fibers are the foundation for asynchronous PHP frameworks (such as ReactPHP and Revolt) and provide a
clean model for writing non-blocking code without callback hell.

This chapter covers the internal implementation of fibers, their C API, and what extension authors must
be aware of.

.. toctree::
    :maxdepth: 2

    fibers/internals.rst
