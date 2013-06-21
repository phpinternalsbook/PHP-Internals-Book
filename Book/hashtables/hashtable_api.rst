HashTables API
==============

There are two sets of APIs working with hashtables: The first is the lower-level ``zend_hash`` API, which will be
discussed in this section. The second one is the array API, which provides some higher-level functions for common
operations and is covered in the next section.

Creating and destroying hashtables
----------------------------------

Hashtables are allocated using ``ALLOC_HASHTABLE()`` and initialized with ``zend_hash_init()``::

    HashTable *myht;

    /* Same as myht = emalloc(sizeof(HashTable)); */
    ALLOC_HASHTABLE(ht);

    zend_hash_init(myht, 1000000, NULL, NULL, 0);

The second argument to ``zend_hash_init()`` is a size hint, which specifies how many elements we expect the hashtable to
have. When ``1000000`` is passed PHP will allocate space for ``2^20 = 1048576`` elements on the first insert. Without
the size hint PHP would first allocate space for 8 elements and then perform multiple resizes once more elements are
inserted (first to 16, then 32, then 64 etc). Every resize requires the ``arBuckets`` to be reallocated and a "rehash"
to occur (which recomputes the collision lists).

Specifying a size hint avoids those unnecessary resize operations and as such improves performance. This only makes
sense for large hashtables though, for small tables passing 0 should be sufficient. In particular note that 8 is the
minimum table size, so it doesn't make a difference if you pass 0 or 2 or 7.

The third argument of ``zend_hash_init()`` should always be ``NULL``: It was previously used to specify a custom hash
function, but this feature is no longer available. The fourth argument is the destructor function for the stored values
and has the following signature::

    typedef void (*dtor_func_t)(void *pDest);

Most of the time this destructor function will be ``ZVAL_PTR_DTOR`` (for storing ``zval *`` values). This is just the
usual ``zval_ptr_dtor()`` function but with a signature that is compatible to ``dtor_func_t``.

The last argument of ``zend_hash_init()`` specifies whether persistent allocation should be used. If you want the
hashtable to live on after the end of the request this argument should be 1. There is a variation of the initialization
function called ``zend_hash_init_ex()``, which accepts an additional boolean ``bApplyProtection`` argument. By setting it
to 0 you can disable recursion protection (which is otherwise enabled by default). This function is used rather rarely,
usually only for internal structures of the engine (like the function or class table).

A hashtable can be destroyed using ``zend_hash_destroy()`` and freed using ``FREE_HASHTABLE()``::

    zend_hash_destroy(myht);

    /* Same as efree(myht); */
    FREE_HASHTABLE(myht);

The ``zend_hash_destroy()`` function will invoke the destructor function on all buckets and free them. While this function
runs the hashtable is in an inconsistent state and can not be used. This is usually okay, but in some rare cases
(especially if the destructor function can call userland code) it may be necessary that the hashtable stays usable
during the destruction process. In this case the ``zend_hash_graceful_destroy()`` and
``zend_hash_graceful_reverse_destroy()`` functions can be used. The former function will destroy the buckets in order of
insertion, the latter in reverse order.

If you want to remove all elements from a hashtable, but not actually destroy it, you can use the ``zend_hash_clean()``
function.

Integer keys
------------

Before looking at the functions used to insert, retrieve and delete integer keys in a hashtable, lets first clarify
what kind of arguments they expect:

Remember that the ``pData`` member of a bucket stores *a pointer* to the actual data. E.g. if you store ``zval *``
values in a hashtable, then ``pData`` will be a ``zval **``. That's why insertions into a hashtable will require you to
pass a ``zval **`` even though you specified ``zval *`` as the data type.

When you retrieve values from a hashtable you'll pass a destination pointer ``pDest`` into which ``pData`` will be
written. In order to write into the pointer using ``*pDest = pData`` yet another level of indirection is needed. So if
``zval *`` is your datatype you'll have to pass a ``zval ***`` to the retrieval function.

As an example of how this looks like, lets consider the ``zend_hash_index_update()`` function, which allows you to
insert and update integer keys::

    HashTable *myht;
    zval *zv;

    ALLOC_HASHTABLE(myht);
    zend_hash_init(myht, 0, NULL, ZVAL_PTR_DTOR, 0);

    MAKE_STD_ZVAL(zv);
    ZVAL_STRING(zv, "foo", 1);

    /* In PHP: $array[42] = "foo" */
    zend_hash_index_update(myht, 42, &zv, sizeof(zval *), NULL);

    zend_hash_destroy(myht);
    FREE_HASHTABLE(myht);

The above example inserts a ``zval *`` containing ``"foo"`` at key ``42``. The fourth argument specifies the used data
type: ``sizeof(zval *)``. As such the third argument, which is the inserted value, must be of type ``zval **``.

The last argument can be used to both insert the value and retrieve it again in the same go::

    zval **zv_dest

    zend_hash_index_update(myht, 42, &zv, sizeof(zval *), (void **) &zv_dest);

Why would you want to do this? After all, you already know the value you inserted, so why would you want to fetch it
again? Remember that hashtables always work on a *copy* of the passed value. So, while the ``zval *`` stored in the
hashtable will be the same one as ``zv``, it will be stored at a different address. In order to do a by-reference
modification of the hashtable value you need the address of this new location, which is exactly what is written into
``zv_dest``.

When storing ``zval *`` values the last argument of the update function is rarely necessary. On the other hand, when
non-pointer data types are used, you'll quite commonly see a pattern where first a temporary structure is created, which
is then inserted into the hashtable and the value in the destination pointer is used for all further work (as changing
the temporary structure would have no effect on the value in the hashtable).

Often you don't want to insert a value at any particular index, but append it at the end of the hashtable. This can be
accomplished using the ``zend_hash_next_index_insert()`` function::

    if (zend_hash_next_index_insert(myht, &zv, sizeof(zval *), NULL) == SUCCESS) {
        Z_ADDREF_P(zv);
    }

The function inserts ``zv`` at the next available integer key. So if the largest used integer key was ``42`` the new
value will be inserted at key ``43``. Note that unlike ``zend_hash_index_update()`` this function can *fail* and you
need to check the return value against ``SUCCESS``/``FAILURE``.

To see when such a failure can occur, consider this example::

    zend_hash_index_update(myht, LONG_MAX, &zv, sizeof(zval *), NULL);

    if (zend_hash_next_index_insert(myht, &zv, sizeof(zval *), NULL) == FAILURE) {
        php_printf("next_index_insert failed!\n");
    }

Here a value is inserted at key ``LONG_MAX``. In this case the next integer key would be ``LONG_MAX + 1``, which
overflows to ``LONG_MIN``. As this overflow behavior is undesirable PHP checks for this special case and leaves
``nNextFreeElement`` at ``LONG_MAX``. When ``zend_hash_next_index_insert()`` is run it will try to insert the value at
key ``LONG_MAX``, but this key is already taken, thus the function fails.

With the above knowledge the three remaining functions from the integer key API should be fairly straightforward:
``zend_hash_index_find()`` gets the value of an index, ``zend_hash_index_exists()`` checks if an index exists without
fetching the value and ``zend_hash_index_del()`` removes an entry. Here's an example for the three functions::

    zval **zv_dest;

    if (zend_hash_index_exists(myht, 42)) {
        php_printf("Index 42 exists\n");
    } else {
        php_printf("Index 42 doesn't exist\n");
    }

    if (zend_hash_index_find(myht, 42, (void **) &zv_dest) == SUCCESS) {
        php_printf("Fetched value of index 42 into zv_dest\n");
    } else {
        php_printf("Couldn't fetch value of index 42 as it doesn't exist :(\n");
    }

    if (zend_hash_index_del(myht, 42) == SUCCESS) {
        php_printf("Removed value at index 42\n");
    } else {
        php_printf("Couldn't remove value at index 42 as it doesn't exist :(\n");
    }

``zend_hash_index_exists()`` return 1 is the index exists, 0 otherwise. The ``find`` and ``del`` functions return
``SUCCESS`` if the value existed and ``FAILURE`` otherwise.

String keys
-----------

String keys are handled very similarly to integer keys. The main difference is that the word ``index`` is removed from
all function names. Of course these functions take a string and its length as parameters rather than an index.

The only caveat is what "string length" means in this context: In the hashtable API the string length
**includes the terminating NUL byte**. In this regard the ``zend_hash`` API differs from nearly all other Zend APIs
which do not include the NUL byte in the string length.

What does this mean practically? When passing a literal string, the string length will be ``sizeof("foo")`` rather than
``sizeof("foo")-1``. When passing a string from a zval, the string length will be ``Z_STRVAL_P(zv)+1`` rather than
``Z_STRVAL_P(zv)``.

Apart from this the functions are used in exactly the same way as the index functions::

    HashTable *myht;
    zval *zv;
    zval **zv_dest;

    ALLOC_HASHTABLE(myht);
    zend_hash_init(myht, 0, NULL, ZVAL_PTR_DTOR, 0);

    MAKE_STD_ZVAL(zv);
    ZVAL_STRING(zv, "bar", 1);

    /* In PHP: $array["foo"] = "bar" */
    zend_hash_update(myht, "foo", sizeof("foo"), &zv, sizeof(zval *), NULL);

    if (zend_hash_exists(myht, "foo", sizeof("foo"))) {
        php_printf("Key \"foo\" exists\n");
    }

    if (zend_hash_find(myht, "foo", sizeof("foo"), (void **) &zv_dest) == SUCCESS) {
        php_printf("Fetched value at key \"foo\" into zv_dest\n");
    }

    if (zend_hash_del(myht, "foo", sizeof("foo")) == SUCCESS) {
        php_printf("Removed value at key \"foo\"\n");
    }

    if (!zend_hash_exists(myht, "foo", sizeof("foo"))) {
        php_printf("Key \"foo\" no longer exists\n");
    }

    if (zend_hash_find(myht, "foo", sizeof("foo"), (void **) &zv_dest) == FAILURE) {
        php_printf("As key \"foo\" no longer exists, zend_hash_find returns FAILURE\n");
    }

    zend_hash_destroy(myht);
    FREE_HASHTABLE(myht);

The above snippet will print:

.. code-block:: none

    Key "foo" exists
    Fetched value at key "foo" into zv_dest
    Removed value at key "foo"
    Key "foo" no longer exists
    As key "foo" no longer exists, zend_hash_find returns FAILURE

Apart from ``zend_hash_update()`` another function is offered for inserting string keys: ``zend_hash_add()``. The
difference between the two functions is the behavior when the key already exists. ``zend_hash_update()`` will overwrite
the value, whereas ``zend_hash_add()`` will return ``FAILURE`` instead.

This is how ``zend_hash_update()`` behaves when you try to overwrite a key::

    zval *zv1, *zv2;
    zval **zv_dest;

    /* ... zval init */

    zend_hash_update(myht, "foo", sizeof("foo"), &zv1, sizeof(zval *), NULL);
    zend_hash_update(myht, "foo", sizeof("foo"), &zv2, sizeof(zval *), NULL);

    if (zend_hash_find(myht, "foo", sizeof("foo"), (void **) &zv_dest) == SUCCESS) {
        if (*zv_dest == zv1) {
            php_printf("Key \"foo\" contains zv1\n");
        }
        if (*zv_dest == zv2) {
            php_printf("Key \"foo\" contains zv2\n");
        }
    }

The above code will print ``Key "foo" contains zv2``, i.e. the value has been overwritten. Now compare with
``zend_hash_add()``::

    zval *zv1, *zv2;
    zval **zv_dest;

    /* ... zval init */

    if (zend_hash_add(myht, "bar", sizeof("bar"), &zv1, sizeof(zval *), NULL) == FAILURE) {
        zval_ptr_dtor(&zv1);
    } else {
        php_printf("zend_hash_add returned SUCCESS as key \"bar\" was unused\n");
    }

    if (zend_hash_add(myht, "bar", sizeof("bar"), &zv2, sizeof(zval *), NULL) == FAILURE) {
        zval_ptr_dtor(&zv2);
        php_printf("zend_hash_add returned FAILURE as key \"bar\" is already taken\n");
    }

    if (zend_hash_find(myht, "bar", sizeof("bar"), (void **) &zv_dest) == SUCCESS) {
        if (*zv_dest == zv1) {
            php_printf("Key \"bar\" contains zv1\n");
        }
        if (*zv_dest == zv2) {
            php_printf("Key \"bar\" contains zv2\n");
        }
    }

The code results in the following output:

.. code-block:: none

    zend_hash_add returned SUCCESS as key "bar" was unused
    zend_hash_add returned FAILURE as key "bar" is already taken
    Key "bar" contains zv1

Here the second call to ``zend_hash_add()`` returns ``FAILURE`` and the value stays at ``zv1``.

Note that while there is a ``zend_hash_add()`` function for string keys there is no equivalent for integer indices. If
you need this kind of behavior you have to either do an ``exists`` call first or make use of a lower-level API::

    _zend_hash_index_update_or_next_insert(myht, 42, &zv, sizeof(zval *), NULL, HASH_ADD ZEND_FILE_LINE_CC)

For all of the above functions there exists a second ``quick`` variant that accepts a precomputed hash value after the
string length. This allows you to compute the hash of a string once and then reuse it across multiple calls::

    ulong h; /* hash value */

    /* ... zval init */

    h = zend_get_hash_value("foo", sizeof("foo"));

    zend_hash_quick_update(myht, "foo", sizeof("foo"), h, &zv, sizeof(zval *), NULL);

    if (zend_hash_quick_find(myht, "foo", sizeof("foo"), h, (void **) &zv_dest) == SUCCESS) {
        php_printf("Fetched value at key \"foo\" into zv_dest\n");
    }

    if (zend_hash_quick_del(myht, "foo", sizeof("foo"), h) == SUCCESS) {
        php_printf("Removed value at key \"foo\"\n");
    }

Using the ``quick`` API improves performance as the hash value does not have to be recomputed on every call. It should
be noted though that this only becomes significant if you are accessing the key a lot (e.g. in a loop). The ``quick``
functions are mostly used in the engine where precomputed hash values are available through various caches and
optimizations.

Apply functions
---------------

Often you don't want to work on any specific key, but want to do an operation on *all* values in the hashtable. PHP
offers two mechanisms for this, the first being the ``zend_hash_apply_*()`` family of functions, which calls a function
for every element in the hashtable. It is available in three variants::

    void zend_hash_apply(HashTable *ht, apply_func_t apply_func TSRMLS_DC);
    void zend_hash_apply_with_argument(HashTable *ht, apply_func_arg_t apply_func, void *argument TSRMLS_DC);
    void zend_hash_apply_with_arguments(HashTable *ht TSRMLS_DC, apply_func_args_t apply_func, int num_args, ...);

The three functions basically do the same thing, but pass on a different number of arguments to the ``apply_func``
function. Here are the respective signatures of the ``apply_func``\s::

    typedef int (*apply_func_t)(void *pDest TSRMLS_DC);
    typedef int (*apply_func_arg_t)(void *pDest, void *argument TSRMLS_DC);
    typedef int (*apply_func_args_t)(void *pDest TSRMLS_DC, int num_args, va_list args, zend_hash_key *hash_key);

As you can see the ``zend_hash_apply()`` function passes no additional arguments to its callback, the
``zend_hash_apply_argument()`` function can pass one additional argument and the ``zend_hash_apply_with_arguments()``
function can pass an arbitrary number of arguments (this is what ``va_list args`` signifies). Furthermore the last
function passes not only the value ``void *pDest``, but also the corresponding ``hash_key``. The ``zend_hash_key``
struct looks as follows::

    typedef struct _zend_hash_key {
        const char *arKey;
        uint nKeyLength;
        ulong h;
    } zend_hash_key;

The members have the same meaning as in a ``Bucket``: If ``nKeyLength == 0`` then ``h`` is the integer key. Otherwise it
is the hash of the string key ``arKey`` of length ``nKeyLength``.

As an example for the usage of these functions, lets implement a simple array dumper similar to ``var_dump``. We will be
using ``zend_hash_apply_with_arguments()``, not because we have to pass many arguments, but because we need the array
key too. We'll start with the main dumping function::

    static void dump_value(zval *zv, int depth) {
        if (Z_TYPE_P(zv) == IS_ARRAY) {
            php_printf("%*carray(%d) {\n", depth * 2, ' ', zend_hash_num_elements(Z_ARRVAL_P(zv)));
            zend_hash_apply_with_arguments(Z_ARRVAL_P(zv), dump_array_values, 1, depth + 1);
            php_printf("%*c}\n", depth * 2, ' ');
        } else {
            php_printf("%*c%Z\n", depth * 2, ' ', zv);
        }
    }

    PHP_FUNCTION(dump_array) {
        zval *array;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "a", &array) == FAILURE) {
            return;
        }

        dump_value(array, 0);
    }

The above code uses some ``php_printf()`` options that might not be generally known: ``%*c`` repeats a character
multiple times. So ``php_printf("%*c", depth * 2, ' ')`` repeats the whitespace character ``depth * 2`` times, which is
responsible for indenting everything by two spaces whenever the depth increases. ``%Z`` converts a zval into a string
and prints it.

Thus the above code prints values directly using ``%Z`` but handles arrays specially: For them an ``array(n) { ... }``
wrapper is printed into which the elements are dumped. Here the apply function comes in::

    zend_hash_apply_with_arguments(Z_ARRVAL_P(zv), dump_array_values, 1, depth + 1);

``dump_array_values`` is the callback function that will be called for every element. ``1`` is the number of arguments
to pass and ``depth + 1`` is that (one) argument. Here's how the function could look like::

    static int dump_array_values(
        void *pDest TSRMLS_DC, int num_args, va_list args, zend_hash_key *hash_key
    ) {
        zval **zv = (zval **) pDest;
        int depth = va_arg(args, int);

        if (hash_key->nKeyLength == 0) {
            php_printf("%*c[%ld]=>\n", depth * 2, ' ', hash_key->h);
        } else {
            php_printf("%*c[\"", depth * 2, ' ');
            PHPWRITE(hash_key->arKey, hash_key->nKeyLength - 1);
            php_printf("\"]=>\n");
        }

        dump_value(*zv, depth);

        return ZEND_HASH_APPLY_KEEP;
    }

The passed ``depth`` argument is fetched using ``depth = va_arg(args, int)``. Any further arguments can be fetched in
the same manner. After that follows some more code for nicely formatting the keys and a recursive call to ``dump_value``
to print the value.

Furthermore the function returns ``ZEND_HASH_APPLY_KEEP``, which is one of four valid return values for apply
callbacks:

``ZEND_HASH_APPLY_KEEP``:
  Keeps the element it just visited and continues traversing the hashtable.
``ZEND_HASH_APPLY_REMOVE``:
  Removes the element it just visited and continues traversing the hashtable.
``ZEND_HASH_APPLY_STOP``
  Keeps the element it just visited and stops traversing the table.
``ZEND_HASH_APPLY_REMOVE | ZEND_HASH_APPLY_STOP``
  Removes the element it just visited and stops traversing the table.

Thus the ``zend_hash_apply_*()`` functions can act as a simple ``array_map()``, but also as an ``array_filter()`` and
have the additional ability to abort the iteration at any point.

Let's try out the dumping function:

.. code-block:: none

    dump_array([1, [2, "foo" => 3]]);
    // output:
    array(2) {
      [0]=>
      1
      [1]=>
      array(2) {
        [0]=>
        2
        ["foo"]=>
        3
      }
    }

The result looks quite a lot like the output of ``var_dump``. If you have a look at the ``php_var_dump()`` function,
you'll find that the same method is used to implement it.

Iteration
---------

The second way to perform an operation on all values of the hashtable is to iterate over it. Hashtable iteration in C
works very similarly to manual array iteration in PHP:

.. code-block:: php

    <?php

    for (reset($array);
         null !== $data = current($array);
         next($array)
    ) {
        // Do something with $data
    }

The equivalent C code for the above loop looks like this::

    zval **data;

    for (zend_hash_internal_pointer_reset(myht);
         zend_hash_get_current_data(myht, (void **) &data) == SUCCESS;
         zend_hash_move_forward(myht)
    ) {
        /* Do something with data */
    }

The above code snippets make use of the internal array pointer (``pInternalPointer``), which usually is a bad idea: This
pointer is part of the hashtable and as such shared among all code using it. For example nested iteration of a hashtable
is not possible when using the internal array pointer (as one loop would change the pointer of the other one).

This is why all iteration functions have a second variant ending in ``_ex``, which works on an external position
pointer. When using this API the current position is stored in a ``HashPosition`` (which is just a typedef to
``Bucket *``) and a pointer to this structure is passed as the last argument to all functions::

    HashPosition pos;
    zval **data;

    for (zend_hash_internal_pointer_reset_ex(myht, &pos);
         zend_hash_get_current_data_ex(myht, (void **) &data, &pos) == SUCCESS;
         zend_hash_move_forward_ex(myht, &pos)
    ) {
        /* Do something with data */
    }

It's also possible to conduct the iteration in reverse order by using ``end`` instead of ``reset`` and
``move_backwards`` instead of ``move_forward``::

    HashPosition pos;
    zval **data;

    for (zend_hash_internal_pointer_end_ex(myht, &pos);
         zend_hash_get_current_data_ex(myht, (void **) &data, &pos) == SUCCESS;
         zend_hash_move_backwards_ex(myht, &pos)
    ) {
        /* Do something with data */
    }

You can additionally fetch the key using the ``zend_hash_get_current_key()`` function, which has the following
signature::

    int zend_hash_get_current_key_ex(
        const HashTable *ht, char **str_index, uint *str_length,
        ulong *num_index, zend_bool duplicate, HashPosition *pos
    );

The return value of this function is the type of the key, which is one of the following values:

``HASH_KEY_IS_LONG``:
  The key is an integer, which will be written into ``num_index``.
``HASH_KEY_IS_STRING``:
  The key is a string, which will be written into ``str_index``. The ``duplicate`` parameter specifies whether the key
  should be written directly or a copy should be made first. Finally the length of the string (once again including the
  NUL byte) is written into ``str_length``.
``HASH_KEY_NON_EXISTANT``:
  This means that we already iterated past the end of the hashtable and there are no more elements. With the loops used
  above this case cannot occur.

To distinguish the different return values this function is typically used in a ``switch`` statement::

    char *str_index;
    uint str_length;
    ulong num_index;

    switch (zend_hash_get_current_key(myht, &str_index, &str_length, &num_index, 0, &pos)) {
        case HASH_KEY_IS_LONG:
            php_printf("%ld", num_index);
            break;
        case HASH_KEY_IS_STRING:
            /* Subtracting 1 as the hashtable lengths include the NUL byte */
            PHPWRITE(str_index, str_length - 1);
            break;
    }

As of PHP 5.5 there is an additional ``zend_hash_get_current_key_zval()`` function which simplifies the common use case
of writing the key into a zval::

    zval *key;
    MAKE_STD_ZVAL(key);
    zend_hash_get_current_key_zval(myht, key, &pos);

.. todo::
    Commenting this out for now, as I haven't yet fully figured out the flags for this function.
    ...
    Furthermore the ``zend_hash_update_current_key()`` function can be used to change the current key (the key itself, not
    the value of the key). The special thing about this function is that it can change the key without changing the order
    of the table. This makes it different from a simple "delete and then insert under a different key" approach, where the
    changed key would appear at the end of the hashtable order.
    ...
    Also might want to add a practical example here. E.g. implement something simple like array_search.

.. todo::
    (zend_hash_reverse_apply)
    zend_hash_next_free_element
    zend_hash_copy
    zend_hash_merge
    zend_hash_merge_ex
    zend_hash_sort
    zend_hash_compare
    zend_hash_minmax
    zend_hash_num_elements
    zend_hash_rehash
    (zend_hash_func)
    ...
    zend_hash_num_elements should be mentioned somewhere at the very start.