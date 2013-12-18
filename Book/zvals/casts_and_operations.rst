Casts and operations
====================

Basic operations
----------------

As zvals are complex structures you can't directly perform basic operations like ``zv1 + zv2`` on them. Doing something
like this will either give you an error or end up adding together two pointers rather than their values.

The "basic" operations like ``+`` are rather complicated when working with zvals, because they have to work across
many types. For example PHP allows you to add together a double with a string containing an integer (``3.14 + "17"``)
or even adding two arrays (``[1, 2, 3] + [4, 5, 6]``).

For this reason PHP provides special functions for performing operations on zvals. Addition for example is handled by
``add_function()``::

    zval *a, *b, *result;
    MAKE_STD_ZVAL(a);
    MAKE_STD_ZVAL(b);
    MAKE_STD_ZVAL(result);

    ZVAL_DOUBLE(a, 3.14);
    ZVAL_STRING(b, "17");

    /* result = a + b */
    add_function(result, a, b TSRMLS_CC);

    php_printf("%Z", result); /* 20.14 */

    /* zvals a, b, result need to be dtored */

Apart from ``add_function()`` there are several other functions implementing binary (two-operand) operations, all with
the same signature::

    int add_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)                 /*  +  */
    int sub_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)                 /*  -  */
    int mul_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)                 /*  *  */
    int div_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)                 /*  /  */
    int mod_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)                 /*  %  */
    int concat_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)              /*  .  */
    int bitwise_or_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)          /*  |  */
    int bitwise_and_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)         /*  &  */
    int bitwise_xor_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)         /*  ^  */
    int shift_left_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)          /*  << */
    int shift_right_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)         /*  >> */
    int boolean_xor_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)         /* xor */
    int is_equal_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)            /*  == */
    int is_not_equal_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)        /*  != */
    int is_identical_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)        /* === */
    int is_not_identical_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)    /* !== */
    int is_smaller_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)          /*  <  */
    int is_smaller_or_equal_function(zval *result, zval *op1, zval *op2 TSRMLS_DC) /*  <= */

All functions take a ``result`` zval into which the result of the operation on ``op1`` and ``op2`` is stored. The
``int`` return value is either ``SUCCESS`` or ``FAILURE`` and indicates whether the operation was successful. Note that
``result`` will always set to some value (like ``false``) even if the operations was not successful.

The ``result`` zvals needs to be allocated and initialized prior to calling one of the functions. Alternatively
``result`` and ``op1`` can be the same, in which case effectively a compound assignment operation is performed::

    zval *a, *b;
    MAKE_STD_ZVAL(a);
    MAKE_STD_ZVAL(b);

    ZVAL_LONG(a, 42);
    ZVAL_STRING(b, "3");

    /* a += b */
    add_function(a, a, b TSRMLS_CC);

    php_printf("%Z", a); /* 45 */

    /* zvals a, b need to be dtored */

Some binary operators are missing from the above list. For example there are no functions for ``>`` and ``>=``. The
reason behind this is that you can implement them using ``is_smaller_function()`` and ``is_smaller_or_equal_function()``
simply by swapping the operands.

Also missing from the list are functions for performing ``&&`` and ``||``. The reasoning here is that the main feature
those operators provide is short-circuiting, which you can't implement with a simple function. If you take
short-circuiting away, both operators are just boolean casts followed by a ``&&`` or ``||`` C-operation.

Apart from the binary operators there are also two unary (single operand) functions::

    int boolean_not_function(zval *result, zval *op1 TSRMLS_DC) /*  !  */
    int bitwise_not_function(zval *result, zval *op1 TSRMLS_DC) /*  ~  */

They work in the same way the other functions, but accept only one operand. The unary ``+`` and ``-`` operations are
missing, because they can be implemented as ``0 + $value`` and ``0 - $value`` respectively, by making use of
``add_function()`` and ``sub_function()``.

The last two functions implement the ``++`` and ``--`` operators::

    int increment_function(zval *op1) /* ++ */
    int decrement_function(zval *op1) /* -- */

These functions don't take a result zval and instead directly modify the passed operand. Note that using these is
different from performing a ``+ 1`` or ``- 1`` with ``add_function()``/``sub_function()``. For example incrementing
``"a"`` will result in ``"b"``, but adding ``"a" + 1`` will result in ``1``.

Comparisons
-----------

The comparison functions introduced above all perform some specific operation, e.g. ``is_equal_function()`` corresponds
to ``==`` and ``is_smaller_function()`` performs a ``<``. An alternative to these is ``compare_function()`` which
computes a more generic result::

    zval *a, *b, *result;
    MAKE_STD_ZVAL(a);
    MAKE_STD_ZVAL(b);
    MAKE_STD_ZVAL(result);

    ZVAL_LONG(a, 42);
    ZVAL_STRING(b, "24");

    compare_function(result, a, b TSRMLS_CC);

    if (Z_LVAL_P(result) < 0) {
        php_printf("a is smaller than b\n");
    } else if (Z_LVAL_P(result) > 0) {
        php_printf("a is greater than b\n");
    } else /*if (Z_LVAL_P(result) == 0)*/ {
        php_printf("a is equal to b\n");
    }

    /* zvals a, b, result need to be dtored */

``compare_function()`` will set the ``result`` zval to one of -1, 1 or 0 corresponding to the relations "smaller than",
"greater than" or "equal" between the passed values.

``compare_function()`` is part of a larger family of comparison functions::

    int compare_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)

    int numeric_compare_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)

    int string_compare_function_ex(zval *result, zval *op1, zval *op2, zend_bool case_insensitive TSRMLS_DC)
    int string_compare_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)
    int string_case_compare_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)

    #ifdef HAVE_STRCOLL
    int string_locale_compare_function(zval *result, zval *op1, zval *op2 TSRMLS_DC)
    #endif

Once again all functions accept two operands and a result zval and return ``SUCCESS``/``FAILURE``.

``compare_function()`` performs a "normal" PHP comparison (i.e. it behaves the same way as the ``<``, ``>`` and ``==``
operators). ``numeric_compare_function()`` compares the operands as numbers by casting them to doubles first.

``string_compare_function_ex()`` compares the operands as strings and has a flag that indicates whether the comparison
should be ``case_insensitive``. Instead of manually specifying that flag you can also use
``string_compare_function()`` (case sensitive) or ``string_case_compare_function()`` (case insensitive). The string
comparison done by these functions is a normal lexicographical string comparison without additional magic for numeric
strings.

``string_locale_compare_function()`` performs a string comparison according to the current locale and is only available
if ``HAVE_STRCOLL`` is defined. As such you must use ``#ifdef HAVE_STRCOLL`` guards whenever you employ the function.
As with anything related to locales, it's best to avoid its use.

Casts
-----

When implementing your own code you will very often deal with only one particular type of zval. E.g. if you are
implementing some string handling code, you'll want to deal only with string zvals and not bother with everything else.
On the other hand you likely also want to support PHPs dynamic type system: PHP allows you to work with numbers as
strings and extension code should honor this as well.

The solution is to cast a zval of arbitrary type to the specific type you'll be working with. In order to support this
PHP provides a ``convert_to_*`` function for every type (apart from resources, as there is no ``(resource)`` cast)::

    void convert_to_null(zval *op);
    void convert_to_boolean(zval *op);
    void convert_to_long(zval *op);
    void convert_to_double(zval *op);
    void convert_to_string(zval *op);
    void convert_to_array(zval *op);
    void convert_to_object(zval *op);

    void convert_to_long_base(zval *op, int base);
    void convert_to_cstring(zval *op);

The last two functions implement non-standard casts: ``convert_to_long_base()`` is the same as ``convert_to_long()``,
but it will make use of a particular base for string to long conversions (e.g. ``16`` for hexadecimals).
``convert_to_cstring()`` behaves like ``convert_to_string()`` but uses a locale-independent double to string conversion.
This means that the result will always use `.` as the decimal separator rather than creating locale-specific strings
like ``"3,14"`` (Germany).

The ``convert_to_*`` functions will directly modify the passed zval::

    zval *zv_ptr;
    MAKE_STD_ZVAL(zv_ptr);
    ZVAL_STRING(zv_ptr, "123 foobar", 1);

    convert_to_long(zv_ptr);

    php_printf("%ld\n", Z_LVAL_P(zv_ptr));

    zval_dtor(&zv_ptr);

If the zval is used in more than one place (refcount > 1) chances are that directly modifying it would result in
incorrect behavior. E.g. if you receive a zval by-value and directly apply a ``convert_to_*`` function to it you will
modify not only the reference to the zval inside the function but also the reference outside of it.

To solve this issue PHP provides an additional set of ``convert_to_*_ex`` macros::

    void convert_to_null_ex(zval **ppzv);
    void convert_to_boolean_ex(zval **ppzv);
    void convert_to_long_ex(zval **ppzv);
    void convert_to_double_ex(zval **ppzv);
    void convert_to_string_ex(zval **ppzv);
    void convert_to_array_ex(zval **ppzv);
    void convert_to_object_ex(zval **ppzv);

These macros take a ``zval**`` and are implemented by performing a ``SEPARATE_ZVAL_IF_NOT_REF()`` before the type
conversion::

    #define convert_to_ex_master(ppzv, lower_type, upper_type)  \
        if (Z_TYPE_PP(ppzv)!=IS_##upper_type) {                 \
            SEPARATE_ZVAL_IF_NOT_REF(ppzv);                     \
            convert_to_##lower_type(*ppzv);                     \
        }

Apart from this the usage is similar to the normal ``convert_to_*`` functions::

    zval **zv_ptr_ptr = /* get function argument */;

    convert_to_long_ex(zv_ptr_ptr);

    php_printf("%ld\n", Z_LVAL_PP(zv_ptr_ptr));

    /* No need to dtor as function arguments are dtored automatically */

But even this will not always be enough. Lets consider a very similar case where a value is fetched from an array::

    zval *array_zv = /* get array from somewhere */;

    /* Fetch array index 42 into zv_dest (how this works is not relevant here) */
    zval **zv_dest;
    if (zend_hash_index_find(Z_ARRVAL_P(array_zv), 42, (void **) &zv_dest) == FAILURE) {
        /* Error: Index not found */
        return;
    }

    convert_to_long_ex(zv_dest);

    php_printf("%ld\n", Z_LVAL_PP(zv_dest));

    /* No need to dtor because array values are dtored automatically */

The use of ``convert_to_long_ex()`` in the above code will prevent modification of references to the value outside the
array, but it will still change the value inside the array itself. In some cases this is the correct behavior, but
typically you want to avoid modifying the array when fetching values from it.

In cases like these there is no way around copying the zval before converting it::

    zval **zv_dest = /* get array value */;
    zval tmp_zv;

    ZVAL_COPY_VALUE(&tmp_zv, *zv_dest);
    zval_copy_ctor(&tmp_zv);

    convert_to_long(&tmp_zv);

    php_printf("%ld\n", Z_LVAL(tmp_zv));

    zval_dtor(&tmp_zv);

The last ``zval_dtor()`` call in the above code is not strictly necessary, because we know that ``tmp_zv`` will be
of type ``IS_LONG``, which is a type that does not require destruction. For conversions to other types like strings or
arrays the dtor call is necessary though.

If the use of to-long or to-double conversions is common in your code, it can make sense to create helper functions which
perform casts without modifying any zval. A sample implementation for long casts::

    long zval_get_long(zval *zv) {
        switch (Z_TYPE_P(zv)) {
            case IS_NULL:
                return 0;
            case IS_BOOL:
            case IS_LONG:
            case IS_RESOURCE:
                return Z_LVAL_P(zv);
            case IS_DOUBLE:
                return zend_dval_to_lval(Z_DVAL_P(zv));
            case IS_STRING:
                return strtol(Z_STRVAL_P(zv), NULL, 10);
            case IS_ARRAY:
                return zend_hash_num_elements(Z_ARRVAL_P(zv)) ? 1 : 0;
            case IS_OBJECT: {
                zval tmp_zv;
                ZVAL_COPY_VALUE(&tmp_zv, zv);
                zval_copy_ctor(&tmp);
                convert_to_long_base(&tmp, 10);
                return Z_LVAL_P(tmp_zv);
            }
        }
    }

The above code will directly return the result of the cast without performing any zval copies (apart from the
``IS_OBJECT`` case where the copy is unavoidable). By making use of the function the array value cast example becomes
much simpler::

    zval **zv_dest = /* get array value */;
    long lval = zval_get_long(*zv_dest);

    php_printf("%ld\n", lval);

PHPs standard library already contains one function of this type, namely ``zend_is_true()``. This function is
functionally equivalent to a bool cast from which value is returned directly::

    zval *zv_ptr;
    MAKE_STD_ZVAL(zv_ptr);

    ZVAL_STRING(zv, "", 1);
    php_printf("%d\n", zend_is_true(zv)); // 0
    zval_dtor(zv);

    ZVAL_STRING(zv, "foobar", 1);
    php_printf("%d\n", zend_is_true(zv)); // 1
    zval_ptr_dtor(&zv);

Another function which avoids unnecessary copies during casting is ``zend_make_printable_zval()``. This function
performs the same string cast as ``convert_to_string()`` but makes use of a different API. The typical usage is as
follows::

    zval *zv_ptr = /* get zval from somewhere */;

    zval tmp_zval;
    int tmp_zval_used;
    zend_make_printable_zval(zv_ptr, &tmp_zval, &tmp_zval_used);

    if (tmp_zval_used) {
        zv_ptr = &tmp_zval;
    }

    PHPWRITE(Z_STRVAL_P(zv_ptr), Z_STRLEN_P(zv_ptr));

    if (tmp_zval_used) {
        zval_dtor(&tmp_zval);
    }

The second parameter to this function is a pointer to a temporary zval and the third parameter is a pointer to an
integer. If the function makes use of the temporary zval, the integer will be set to one, zero otherwise.

Based on ``tmp_zval_used`` you can then decide whether to use the original zval or the temporary copy. Very commonly
the temporary zval is simply assigned to the original zval using ``zv_ptr = &tmp_zval``. This allows you to always work
with ``zv_ptr`` rather than having conditionals everywhere to choose between the two.

Finally you need to dtor the temporary zval using ``zval_dtor(&tmp_zval)``, but only if it was actually used.

Another function that is related to casting is ``is_numeric_string()``. This function checks whether a string is
"numeric" and extracts the value into either a long or a double::

    long lval;
    double dval;

    switch (is_numeric_string(Z_STRVAL_P(zv_ptr), Z_STRLEN_P(zv_ptr), &lval, &dval, 0)) {
        case IS_LONG:
            /* String is an integer those value was put into `lval` */
            break;
        case IS_DOUBLE:
            /* String is a double those value was put into `dval` */
            break;
        default:
            /* String is not numeric */
    }

The last argument to this function is called ``allow_errors``. Setting it to ``0`` will reject strings like
``"123abc"``, whereas setting it to ``1`` will silently allow them (with value ``123``). A third value ``-1`` provides
an intermediate solution, which accepts the string, but throws a notice.

It is helpful to know that this function also accepts hexadecimal numbers in the ``0xabc`` format. In this it differs
from ``convert_to_long()`` and ``convert_to_double()`` which would cast ``"0xabc"`` to zero.

``is_numeric_string()`` is particularly useful in cases where you can work with both integer and floating point numbers,
but don't want to incur the precision loss associated with using doubles for both cases. To help this use case, there
is an additional ``convert_scalar_to_number()`` function, which accepts a zval and converts non-array values to either
a long or a double (using ``is_numeric_string()`` for strings). This means that the converted zval will have type
``IS_LONG``, ``IS_DOUBLE`` or ``IS_ARRAY``. The usage is the same as for the ``convert_to_*()`` functions::

    zval *zv_ptr;
    MAKE_STD_ZVAL(zv_ptr);
    ZVAL_STRING(zv_ptr, "3.141", 1);

    convert_scalar_to_number(zv_ptr);
    switch (Z_TYPE_P(zv_ptr)) {
        case IS_LONG:
            php_printf("Long: %ld\n", Z_LVAL_P(zv_ptr));
            break;
        case IS_DOUBLE:
            php_printf("Double: %G\n", Z_DVAL_P(zv_ptr));
            break;
        case IS_ARRAY:
            /* Likely throw an error here */
            break;
    }

    zval_dtor(&zv_ptr);

    /* Double: 3.141 */

Once again there also is a ``convert_scalar_to_number_ex()`` variant of this function, which accepts a ``zval**`` and
will separate it before the conversion.
