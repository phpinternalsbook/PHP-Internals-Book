Symtable and array API
======================

The hashtable API allows you to work with values of any type, but in the vast majority of cases the values will be
zvals. Using the ``zend_hash`` API with zvals can often be somewhat cumbersome, as you need to handle zval allocation
and initialization yourself. This is why PHP provides a second set of APIs specifically aimed at this use case. Before
introducing these simplified APIs we will have a look at a special kind of hashtable that PHP arrays make use of.

Symtables
---------

One of the core concepts behind the design of PHP is that integers and strings containing integers should be
interchangeable. This also applies to arrays where the keys ``42`` and ``"42"`` should be considered the same. This is
not the case though with ordinary hashtables: They strictly distinguish the key types and it's okay to have both the
key ``42`` and ``"42"`` in the same table (with different values).

This is why there is an additional *symtable* (symbol table) API, which is a thin wrapper around some hashtable
functions which converts integral string keys to actual integer keys. For example, this is how the
``zend_symtable_find()`` function is defined::

    static inline int zend_symtable_find(
        HashTable *ht, const char *arKey, uint nKeyLength, void **pData
    ) {
        ZEND_HANDLE_NUMERIC(arKey, nKeyLength, zend_hash_index_find(ht, idx, pData));
        return zend_hash_find(ht, arKey, nKeyLength, pData);
    }

The implementation of the ``ZEND_HANDLE_NUMERIC()`` macro will not be considered in detail here, only the functionality
behind it is important: If ``arKey`` contains a decimal integer between ``LONG_MIN`` and ``LONG_MAX``, then that
integer is written into ``idx`` and ``zend_hash_index_find()`` is called with it. In all other cases the code will
continue to the next line, where ``zend_hash_find()`` will be invoked.

Apart from ``zend_symtable_find()`` the following functions are part of the symtable API, again with the same behavior
as their hashtable counterparts, but including string to integer normalization::

    static inline int zend_symtable_exists(HashTable *ht, const char *arKey, uint nKeyLength);
    static inline int zend_symtable_del(HashTable *ht, const char *arKey, uint nKeyLength);
    static inline int zend_symtable_update(
        HashTable *ht, const char *arKey, uint nKeyLength, void *pData, uint nDataSize, void **pDest
    );
    static inline int zend_symtable_update_current_key_ex(
        HashTable *ht, const char *arKey, uint nKeyLength, int mode, HashPosition *pos
    );

Additionally there are two macros for creating symtables::

    #define ZEND_INIT_SYMTABLE_EX(ht, n, persistent) \
        zend_hash_init(ht, n, NULL, ZVAL_PTR_DTOR, persistent)

    #define ZEND_INIT_SYMTABLE(ht) \
        ZEND_INIT_SYMTABLE_EX(ht, 2, 0)

As you can see these macros are just ``zend_hash_init()`` calls using ``ZVAL_PTR_DTOR`` as the destructor. As such
these macros are not directly related to the string to integer casting behavior described above.

Let's give this new set of functions a try::

    HashTable *myht;
    zval *zv1, *zv2;
    zval **zv_dest;

    ALLOC_HASHTABLE(myht);
    ZEND_INIT_SYMTABLE(myht);

    MAKE_STD_ZVAL(zv1);
    ZVAL_STRING(zv1, "zv1", 1);

    MAKE_STD_ZVAL(zv2);
    ZVAL_STRING(zv2, "zv2", 1);

    zend_hash_index_update(myht, 42, &zv1, sizeof(zval *), NULL);
    zend_symtable_update(myht, "42", sizeof("42"), &zv2, sizeof(zval *), NULL);

    if (zend_hash_index_find(myht, 42, (void **) &zv_dest) == SUCCESS) {
        php_printf("Value at key 42 is %Z\n", *zv_dest);
    }

    if (zend_symtable_find(myht, "42", sizeof("42"), (void **) &zv_dest) == SUCCESS) {
        php_printf("Value at key \"42\" is %Z\n", *zv_dest);
    }

    zend_hash_destroy(myht);
    FREE_HASHTABLE(myht);

This code will print:

.. code-block:: none

    Value at key 42 is zv2
    Value at key "42" is zv2

Thus both ``update`` calls wrote to the same element (the second one overwriting the first one) and both ``find`` calls
also found the same element.

Array API
---------

Now we have all the prerequisites to look at the array API. This API no longer works directly on hashtables, but rather
accepts zvals from which the hashtable is extracted using ``Z_ARRVAL_P()``.

The first two functions from this API are ``array_init()`` and ``array_init_size()``, which initialize a hashtable
into a zval. The former function takes only the target zval, whereas the latter takes an additional size hint::

    /* Create empty array into return_value */
    array_init(return_value);

    /* Create empty array with expected size 1000000 into return_value */
    array_init_size(return_value, 1000000);

The remaining functions of this API all deal with inserting values into an array. There are four families of functions
which look as follows::

    /* Insert at next index */
    int add_next_index_*(zval *arg, ...);
    /* Insert at specific index */
    int add_index_*(zval *arg, ulong idx, ...);
    /* Insert at specific key */
    int add_assoc_*(zval *arg, const char *key, ...);
    /* Insert at specific key of length key_len (for binary safety) */
    int add_assoc_*_ex(zval *arg, const char *key, uint key_len, ...);

Here ``*`` is a placeholder for a type and ``...`` a placeholder for the type-specific arguments. The valid values for
them are listed in the following table:

.. list-table::
    :header-rows: 1
    :widths: 8 20

    * - Type
      - Additional arguments
    * - ``null``
      - none
    * - ``bool``
      - ``int b``
    * - ``long``
      - ``long n``
    * - ``double``
      - ``double d``
    * - ``string``
      - ``const char *str, int duplicate``
    * - ``stringl``
      - ``const char *str, uint length, int duplicate``
    * - ``resource``
      - ``int r``
    * - ``zval``
      - ``zval *value``

As an example for the usage of these functions, let's just create a dummy array with elements of various types::

    PHP_FUNCTION(make_array) {
        zval *zv;

        array_init(return_value);

        add_index_long(return_value, 10, 100);
        add_index_double(return_value, 20, 3.141);
        add_index_string(return_value, 30, "foo", 1);

        add_next_index_bool(return_value, 1);
        add_next_index_stringl(return_value, "\0bar", sizeof("\0bar")-1, 1);

        add_assoc_null(return_value, "foo");
        add_assoc_long(return_value, "bar", 42);

        add_assoc_double_ex(return_value, "\0bar", sizeof("\0bar"), 1.61);

        /* For some things you still have to manually create a zval... */
        MAKE_STD_ZVAL(zv);
        object_init(zv);
        add_next_index_zval(return_value, zv);
    }

The ``var_dump()`` output of this array looks as follows (with NUL-bytes replaced by ``\0``):

.. code-block:: none

    array(9) {
      [10]=>
      int(100)
      [20]=>
      float(3.141)
      [30]=>
      string(3) "foo"
      [31]=>
      bool(true)
      [32]=>
      string(4) "\0bar"
      ["foo"]=>
      NULL
      ["bar"]=>
      int(42)
      ["\0bar"]=>
      float(1.61)
      [33]=>
      object(stdClass)#1 (0) {
      }
    }

Looking at the above code you may notice that the array API is even more inconsistent in regard to string lengths: The
key length passed to the ``_ex`` functions *includes* the terminating NUL-byte, whereas the string length passed to the
``stringl`` functions *excludes* the NUL-byte.

Furthermore it should be noted that while these functions start with ``add`` they behave like ``update`` functions in
that they overwrite previously existing keys.

There are several additional ``add_get`` functions which both insert a value and fetch it again (analogous to the last
parameter of the ``zend_hash_update`` functions). As they are virtually never used they will not be discussed here and
are mentioned only for the sake of completeness.

This concludes our walk through the hashtable, symtable and array APIs.