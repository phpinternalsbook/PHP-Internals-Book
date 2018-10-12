Zend engine
===========

The Zend engine is a set of components that make PHP what it is. The most important Zend engine component is the
*Zend Virtual Machine*, which is composed of the *Zend Compiler* and the *Zend Executor* components. We could also add
the OPCache zend extension in such category. Those three components are the heart of PHP (or the brain, you choose),
they are critical and they are the most complex parts of all the PHP source code. In the current chapter, we'll try to
open them and detail them.

Contents:

.. toctree::
    :maxdepth: 2

    zend_engine/zend_compiler.rst
    zend_engine/zend_executor.rst
    zend_engine/zend_opcache.rst

