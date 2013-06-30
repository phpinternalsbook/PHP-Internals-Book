Hash algorithm and collisions
=============================

In this final section on hashtables, we'll have a closer look at worst-case collision scenarios and some properties of
the hashing function that PHP employs. While this knowledge is not necessary for the usage of the hashtable APIs it
should give you a better understanding of the hashtable structure and its limitations.

Analyzing collisions
--------------------

In order to simplify collision analysis, let's first write a helper function ``array_collision_info()`` which will
take an array and tell us which keys collide into which index. In order to do so we'll go through the ``arBuckets`` and
for every index create an array that contains some information about all buckets at that index::

    PHP_FUNCTION(array_collision_info) {
        HashTable *hash;
        zend_uint i;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_DC, "h", &hash) == FAILURE) {
            return;
        }

        array_init(return_value);

        /* Empty hashtables may not yet be initialized */
        if (hash->nNumOfElements == 0) {
            return;
        }

        for (i = 0; i < hash->nTableSize; ++i) {
            /* Create array of elements at this nIndex */
            zval *elements;
            Bucket *bucket;

            MAKE_STD_ZVAL(elements);
            array_init(elements);
            add_next_index_zval(return_value, elements);

            bucket = hash->arBuckets[i];
            while (bucket != NULL) {
                zval *element;

                MAKE_STD_ZVAL(element);
                array_init(element);
                add_next_index_zval(elements, element);

                add_assoc_long(element, "hash", bucket->h);

                if (bucket->nKeyLength == 0) {
                    add_assoc_long(element, "key", bucket->h);
                } else {
                    add_assoc_stringl(
                        element, "key", (char *) bucket->arKey, bucket->nKeyLength - 1, 1
                    );
                }

                {
                    zval **data = (zval **) bucket->pData;
                    Z_ADDREF_PP(data);
                    add_assoc_zval(element, "value", *data);
                }

                bucket = bucket->pNext;
            }
        }
    }

The code is also a nice usage example for the ``add_`` functions from the previous section. Let's try the function out::

    var_dump(array_collision_info([2 => 0, 5 => 1, 10 => 2]));

    // Output (reformatted a bit):

    array(8) {
      [0] => array(0) {}
      [1] => array(0) {}
      [2] => array(2) {
        [0] => array(3) {
          ["hash"]  => int(10)
          ["key"]   => int(10)
          ["value"] => int(2)
        }
        [1] => array(3) {
          ["hash"]  => int(2)
          ["key"]   => int(2)
          ["value"] => int(0)
        }
      }
      [3] => array(0) {}
      [4] => array(0) {}
      [5] => array(1) {
        [0] => array(3) {
          ["hash"]  => int(5)
          ["key"]   => int(5)
          ["value"] => int(1)
        }
      }
      [6] => array(0) {}
      [7] => array(0) {}
    }

There are several things you can see from this output (most of which you should already be aware of):

* The outer array has 8 elements, even though only 3 were inserted. This is because 8 is the default initial table
  size.
* For integers the hash and the key are always the same.
* Even though the hashes are all different, we still have a collision at ``nIndex == 2`` because 2 % 8 is 2, but
  10 % 8 is also 2.
* The linked collision resolution lists contain the elements in reverse order of insertion. (This is the easiest way
  to implement it.)

Index collisions
----------------

The goal now is to create a worst-case collision scenario where *all* hash keys collide. There are two ways to
accomplish this and we'll start with the easier one: Rather than creating collisions in the hash function, we'll
create the collisions in the index (which is the hash modulo the table size).

For integer keys this is particularly easy, because no real hashing operation is applied to them. The index will simply
be ``key % nTableSize``. Finding collisions for this expression is trivial, e.g. any key that is a multiple of the
table size will collide. If the table size if 8, then the indices will be 0 % 8 = 0, 8 % 8 = 0, 16 % 8 = 0, 24 % 8 = 0,
etc.

Here is a PHP script demonstrating this scenario:

.. code-block:: php

    <?php

    $size = pow(2, 16); // any power of 2 will do

    $startTime = microtime(true);

    // Insert keys [0, $size, 2 * $size, 3 * $size, ..., ($size - 1) * $size]

    $array = array();
    for ($key = 0, $maxKey = ($size - 1) * $size; $key <= $maxKey; $key += $size) {
        $array[$key] = 0;
    }

    $endTime = microtime(true);

    printf("Inserted %d elements in %.2f seconds\n", $size, $endTime - $startTime);
    printf("There are %d collisions at index 0\n", count(array_collision_info($array)[0]));

This is the output I get (the results will be different for your machine, but should have the same order of magnitude):

.. code-block:: none

    Inserted 65536 elements in 34.05 seconds
    There are 65536 collisions at index 0

Of course thirty seconds to insert a handful of elements is *very* slow. What happened? As we have constructed a
scenario where all hash keys collide the performance of inserts degenerates from O(1) to O(n): On every insert PHP has
to walk the collision list for the index in order to check whether an element with the same key already exists. Usually
this is not a problem as the collision list contains only one or two buckets. In the degenerate case on the other hand
*all* elements will be in that list.

As such PHP has to perform n inserts with O(n) time, which gives a total execution time of O(n^2). Thus instead of doing
2^16 operations about 2^32 will have to be done.

Hash collisions
---------------

Now that we successfully created a worst-case scenario using index collisions, let's do the same using actual hash
collisions. As this is not possible using integer keys, we'll have to take a look at PHP's string hashing function,
which is defined as follows::

    static inline ulong zend_inline_hash_func(const char *arKey, uint nKeyLength)
    {
        register ulong hash = 5381;

        /* variant with the hash unrolled eight times */
        for (; nKeyLength >= 8; nKeyLength -= 8) {
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
            hash = ((hash << 5) + hash) + *arKey++;
        }
        switch (nKeyLength) {
            case 7: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 6: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 5: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 4: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 3: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 2: hash = ((hash << 5) + hash) + *arKey++; /* fallthrough... */
            case 1: hash = ((hash << 5) + hash) + *arKey++; break;
            case 0: break;
            EMPTY_SWITCH_DEFAULT_CASE()
        }
        return hash;
    }

After removing the manual loop-unrolling the function will look like this::

    static inline ulong zend_inline_hash_func(const char *arKey, uint nKeyLength)
    {
        register ulong hash = 5381;

        for (uint i = 0; i < nKeyLength; ++i) {
            hash = ((hash << 5) + hash) + arKey[i];
        }

        return hash;
    }

The ``hash << 5 + hash`` expression is the same as ``hash * 32 + hash`` or just ``hash * 33``. Using this we can further
simplify the function::

    static inline ulong zend_inline_hash_func(const char *arKey, uint nKeyLength)
    {
        register ulong hash = 5381;

        for (uint i = 0; i < nKeyLength; ++i) {
            hash = hash * 33 + arKey[i];
        }

        return hash;
    }

This hash function is called *DJBX33A*, which stands for "Daniel J. Bernstein, Times 33 with Addition". It is one of the
simplest (and as such also one of the fastest) string hashing functions there is.

Thanks to the simplicity of the hash function finding collisions is not hard. We'll start with two-character collisions,
i.e. we are looking for two strings ``ab`` and ``cd``, which have the same hash:

.. code-block:: none

        hash(ab) = hash(cd)
    <=> (5381 * 33 + a) * 33 + b = (5381 * 33 + c) * 33 + d
    <=> a * 33 + b = c * 33 + d
    <=> c = a + n
        d = b - 33 * n
        where n is an integer

This tells us that we can get a collision by taking a two-char string, incrementing the first char by one and
decrementing the second char by 33. Using this technique we can create groups of 8 strings which all collide. Here is
an example of such a collision group:

.. code-block:: php

    <?php
    $array = [
        "E" . chr(122)  => 0,
        "F" . chr(89)   => 1,
        "G" . chr(56)   => 2,
        "H" . chr(23)   => 3,
        "I" . chr(-10)  => 4,
        "J" . chr(-43)  => 5,
        "K" . chr(-76)  => 6,
        "L" . chr(-109) => 7,
    ];

    var_dump(array_collision_info($array));

The output shows that indeed all the keys collide with hash ``193456164``::

    array(8) {
      [0] => array(0) {}
      [1] => array(0) {}
      [2] => array(0) {}
      [3] => array(0) {}
      [4] => array(8) {
        [0] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "L\x93"
          ["value"] => int(7)
        }
        [1] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "K´"
          ["value"] => int(6)
        }
        [2] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "JÕ"
          ["value"] => int(5)
        }
        [3] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "Iö"
          ["value"] => int(4)
        }
        [4] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "H\x17"
          ["value"] => int(3)
        }
        [5] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "G8"
          ["value"] => int(2)
        }
        [6] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "FY"
          ["value"] => int(1)
        }
        [7] => array(3) {
          ["hash"]  => int(193456164)
          ["key"]   => string(2) "Ez"
          ["value"] => int(0)
        }
      }
      [5] => array(0) {}
      [6] => array(0) {}
      [7] => array(0) {}
    }

Once we got one collision group, constructing more collisions is even easier. To do so we make use of the following
property of DJBX33A: If two equal-length strings ``$str1`` and ``$str2`` collide, then ``$prefix.$str1.$postfix`` and
``$prefix.$str2.$postfix`` will collide as well. It's easy to prove that this is indeed true:

.. code-block:: none

      hash(prefix . str1 . postfix)
    = hash(prefix) * 33^a + hash(str1) * 33^b + hash(postfix)
    = hash(prefix) * 33^a + hash(str2) * 33^b + hash(postfix)
    = hash(prefix . str2 . postfix)

      where a = strlen(str1 . postfix) and b = strlen(postfix)

Thus, if ``Ez`` and ``FY`` collide, so will ``abcEzefg`` and ``abcFYefg``. This is also the reason why we could ignore
the trailing NUL-byte that is also part of the hash in the previous considerations: It would result in a different hash,
but the collisions would still be present.

Using this property large sets of collisions can be created by taking a known set of collisions and concatenating them
in every possible way. E.g. if we know that ``Ez`` and ``FY`` collide, then we also know that all of ``EzEzEz``,
``EzEzFY``, ``EzFYEz``, ``EzFYFY``, ``FYEzEz``, ``FYEzFY``, ``FYFYEz`` and ``FYFYFY`` will collide. With this method we
can create arbitrarily large sets of collisions.