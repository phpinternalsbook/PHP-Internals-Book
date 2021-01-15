Casts and operations
====================

Casts
-----

In many situations, you expect to receive a zval of a specific type. In this case, you could strictly check for the
desired type::

    if (Z_TYPE_P(val) != IS_STRING) {
        zend_type_error("Expected string");
        return;
    }

Alternatively, you can perform a cast to the desired type. There are two ways in which casts can be performed: The first
is to actually change the type of the zval using one of the ``convert_to_*`` functions::

    convert_to_string(val);
    // Z_TYPE_P(val) == IS_STRING is guaranteed here.

Similar functions exist for all the other types that have a meaningful type cast::

    void convert_to_null(zval *op);
    void convert_to_boolean(zval *op);
    void convert_to_long(zval *op);
    void convert_to_double(zval *op);
    void convert_to_string(zval *op);
    void convert_to_array(zval *op);
    void convert_to_object(zval *op);

In addition, the ``convert_scalar_to_number()`` function can be used to convert the zval into either an integer or a
float, with the caveat that arrays stay as arrays::

    convert_scalar_to_number(val);
    switch (Z_TYPE_P(val)) {
        case IS_LONG:
            php_printf("Long: " ZEND_LONG_FMT "\n", Z_LVAL_P(val));
            break;
        case IS_DOUBLE:
            php_printf("Long: %H\n", Z_DVAL_P(val));
            break;
        case IS_ARRAY:
            php_printf("Array\n");
            break;
        ZEND_EMPTY_SWITCH_DEFAULT_CASE()
    }

Because ``convert_to_*`` modifies zvals in-place, care is needed to maintain copy-on-write semantics. A common mistake
is to write code like the following::

    zval *val;
    ZEND_HASH_FOREACH_VAL(Z_ARRVAL_P(array), val) {
        convert_to_string(val);
        // Use val as string.
    }

Here, we want to iterate over an array and treat all elements as strings. However, as ``convert_to_string()`` operates
in-place, this means that the array actually gets modified. As such, this code is only legal if you own the array
uniquely. Otherwise, it would be necessary to perform a separation first::

    zval *val;
    SEPARATE_ARRAY(array);
    ZEND_HASH_FOREACH_VAL(Z_ARRVAL_P(array), val) {
        convert_to_string(val);
        // Use val as string.
    }

The second set of cast APIs avoids this issue by returning the converted value instead of changing the type of the zval
itself. In the cases where it can be used, this is usually more convenient, more efficient and safer (with regard to
copy-on-write). When converting to booleans, integers and floats, we simply receive a ``bool``, ``zend_long``, or
``double`` result and are done::

    bool b = zend_is_true(val);
    zend_long l = zval_get_long(val);
    double d = zval_get_double(val);

For strings, we receive a ``zend_string *`` result, which we must release afterwards. If the value is already a string,
this will simply increment the refcount. If it's not a string, it will either return an existing interned string, or
allocate a new one::

    zend_string *str = zval_get_string(val);
    // Do something with str.
    zend_string_release(str);

For this kind of temporary usage, where we don't retain a long-term reference to ``str``, an additional optimized API
exists::

    zend_string *tmp_str;
    zend_string *str = zval_get_tmp_string(val, &tmp_str);
    // Do something with str.
    zend_tmp_string_release(str);

This API works the same way as ``zval_get_string()``, but avoids a refcount increment and decrement for the common
case where the value is already a string.

When it comes to conversions to strings in particular, there is one additional issue to consider: ``__toString()``
methods can throw (actually, conversions to int and float can throw as well, but this issue is usually ignored). This
can be handled by checking ``EG(exception)`` after a string conversion::

    zend_string *str = zval_get_string(val);
    if (EG(exception)) {
        // zend_string_release(str) is safe, but not necessary here.
        return;
    }
    zend_string_release(str);

However, the more idiomatic and efficient way to handle this situation, is to use ``try`` variants of these functions
instead, which will indicate whether an exception has been thrown in their return value::

    if (!try_convert_to_string(val)) {
        // Exception thrown.
        return;
    }

    zend_string *str = zval_try_get_string(val);
    if (!str) {
        // Exception thrown.
        return;
    }
    zend_string_release(str);

    zend_string *tmp_str;
    zend_string *str = zend_try_get_tmp_string(val, &tmp_str);
    if (!str) {
        // Exception thrown.
        return;
    }
    zend_tmp_string_release(tmp_str);

Operations
----------

Userland operations like ``$op1 + $op2`` are implemented through corresponding functions like ``add_function()``
internally, which accept a result out-parameter, followed by the input operands::

    zval *op1 = /* ... */, *op2 = /* ... */;
    zval result;
    if (add_function(&result, op1, op2) == FAILURE) {
        // Exception thrown.
        return;
    }
    // Do something with result.
    zval_ptr_dtor(&result);

It should be noted that these functions are rather rarely used in practice, as most code works with zvals of specific
types, rather than operating on completely arbitrary values. The full set of functions is::

    zend_result add_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 + $op2 */
    zend_result sub_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 - $op2 */
    zend_result mul_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 * $op2 */
    zend_result pow_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 ** $op2 */
    zend_result div_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 / $op2 */
    zend_result mod_function(zval *result, zval *op1, zval *op2);                 /* $result = $op1 % $op2 */
    zend_result bitwise_or_function(zval *result, zval *op1, zval *op2);          /* $result = $op1 | $op2 */
    zend_result bitwise_and_function(zval *result, zval *op1, zval *op2);         /* $result = $op1 & $op2 */
    zend_result bitwise_xor_function(zval *result, zval *op1, zval *op2);         /* $result = $op1 ^ $op2 */
    zend_result boolean_xor_function(zval *result, zval *op1, zval *op2);         /* $result = $op1 xor $op2 */
    zend_result shift_left_function(zval *result, zval *op1, zval *op2);          /* $result = $op1 << $op2 */
    zend_result shift_right_function(zval *result, zval *op1, zval *op2);         /* $result = $op1 >> $op2 */
    zend_result concat_function(zval *result, zval *op1, zval *op2);              /* $result = $op1 . $op2 */

    zend_result bitwise_not_function(zval *result, zval *op1);                    /* $result = ~$op1 */
    zend_result boolean_not_function(zval *result, zval *op1);                    /* $result = !$op1 */

    zend_result increment_function(zval *op);                                     /* ++$op */
    zend_result decrement_function(zval *op);                                     /* --$op */

    zend_result compare_function(zval *result, zval *op1, zval *op2);             /* $result = $op1 <=> $op2 */
    zend_result is_equal_function(zval *result, zval *op1, zval *op2);            /* $result = $op1 == $op2 */
    zend_result is_not_equal_function(zval *result, zval *op1, zval *op2);        /* $result = $op1 != $op2 */
    zend_result is_identical_function(zval *result, zval *op1, zval *op2);        /* $result = $op1 === $op2 */
    zend_result is_not_identical_function(zval *result, zval *op1, zval *op2);    /* $result = $op1 !== $op2 */
    zend_result is_smaller_function(zval *result, zval *op1, zval *op2);          /* $result = $op1 < $op2 */
    zend_result is_smaller_or_equal_function(zval *result, zval *op1, zval *op2); /* $result = $op1 <= $op2 */
    /* $op1 > $op2 is same as $op2 < $op1 */
    /* $op1 >= $op2 is same as $op2 <= $op1 */

For comparisons, there are two more variants that return the comparison result, instead of placing it in a zval::

    bool zend_is_identical(zval *op1, zval *op2);
    int zend_compare(zval *op1, zval *op2);

``zend_compare()`` returns a 3-way comparison result like the ``<=>`` operator in PHP, which is less than, equal to,
or greater than zero depending on whether ``op1`` is smaller, equal to, or greater than ``op2``.

Finally, there are a number of variants that have a ``fast_`` prefix. These are optimized implementations that
restrict the arguments to certain types, or inline part of the implementation and/or implement it using inline
assembly::

    /* op1 must have type IS_LONG, implementation uses inline assembly. */
    static zend_always_inline void fast_long_increment_function(zval *op1);
    static zend_always_inline void fast_long_decrement_function(zval *op1);
    /* op1 and op2 must have type IS_LONG, implementation uses inline assembly. */
    static zend_always_inline void fast_long_add_function(zval *result, zval *op1, zval *op2);
    static zend_always_inline void fast_long_sub_function(zval *result, zval *op1, zval *op2);
    /* op1, op2 may have any type, but IS_LONG and IS_DOUBLE addition is inlined. */
    static zend_always_inline zend_result fast_add_function(zval *result, zval *op1, zval *op2);
    /* op1, op2 may have any type, but IS_LONG, IS_DOUBLE and IS_STRING equality is inlined. */
    static zend_always_inline bool fast_equal_check_function(zval *op1, zval *op2);
    /* op1 must have type IS_LONG, op2 can have any type. */
    static zend_always_inline bool fast_equal_check_long(zval *op1, zval *op2);
    /* op1 must have type IS_DOUBLE, op2 can have any type. */
    static zend_always_inline bool fast_equal_check_string(zval *op1, zval *op2);
    /* op1, op2 may have any type, but part of the implementation is inlined. */
    static zend_always_inline bool fast_is_identical_function(zval *op1, zval *op2);
    static zend_always_inline bool fast_is_not_identical_function(zval *op1, zval *op2);
