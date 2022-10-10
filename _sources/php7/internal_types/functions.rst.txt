Functions
========================

The body of PHP functions are represented with the ``zend_function`` structure.
However, handling them is rarely done as they are solely needed for the VM.
In general PHP ``callable`` s are what will need to be dealt with, which are represented by the pair of
``zend_fcall_info``/``zend_fcall_info_cache`` structures.


TODO: Detail ``zend_function``

.. toctree::
    :maxdepth: 2

    functions/callables.rst