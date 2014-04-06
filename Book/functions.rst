Functions
=========



Contents:

.. toctree::
    :maxdepth: 2

    functions/registration.rst
    functions/arguments_and_return_values.rst
..
    functions/structure.rst
    functions/arguments.rst
    functions/param_parsing.rst
    functions/return_values.rst
    functions/error_handling.rst

..
    zend_function_entry
    zend_function
    Anatomy of a PHP function from internal point of view
        PHP_FUNCTION definition
        PHP_FE registration
    Argument information
        Accepting parameters
        zend_arg_info structure
        ZEND_*_ARG_INFO*
    Parameter parsing
        zend_parse_parameters()
        zend_parse_parameters_ex(), ZEND_PARSE_PARAMS_QUIET
        zend_parse_method_parameters() [Maybe in OO section?]
        zend_parse_parameters_none()
        zend_parse_parameter() [? is not really used]
        and underlying functions
    Other argument fetching APIs
        zend_get_parameters[_ex]()
        zend_get_parameters_array[_ex]()
    Returning values from your functions
        RETURN_*, RETVAL_* macros
    Error handling
        Error reporting, php_error_docref*
        correct freeing in case of errors
