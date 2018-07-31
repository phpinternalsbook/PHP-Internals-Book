Strings management
==================

Any program needs to manage strings. Managing is like allocating, searching, concatenating, extending, shrinking etc..

Many operations are needed with strings. Although the C standard library provides many functions for such a goal,
C classical strings, aka ``char *`` (or ``char []``) are usually a little bit weak to use as-is in a strong program
like PHP is.

Thus, PHP designed a layer on top of C strings: ``zend_strings``. Also, another API exists that implements common string
operations both for C classical strings, or for ``zend_strings``: ``smart_str`` API.

.. toctree::
    :maxdepth: 2

    strings/zend_strings.rst
    strings/smart_str.rst
    strings/printing_functions.rst
