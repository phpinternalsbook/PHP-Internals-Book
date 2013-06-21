Hash algorithm and collisions
=============================

...

::

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

...

Let's recall how all this works: When inserting a data, the (usually) provided key may be of two types: int or string.
If the key is a string, it then passes through the hash algorithm, which is *DJBX33A* in PHP, and an integer comes out
from this function. If the key were an integer, it is just used as-is. In both cases, we end up having a hash key with
an integer of type ``unsigned long`` (ulong), with no limit in its bounds. So we would need to allocate an array
(``arBuckets``) that should be referenced from 0 to ``sizeof(ulong)``, something like 18446744073709551615 on 64bits
platform, which is clearly impossible. The problem is that the actual hash key we computed is just too big and has no
bounds on the unsigned long range, it then cannot be used as-is as a C array index because the array would have been too
huge to fit in memory. What is then done as a second step, is that the hash key gets narrow-bounded, using a mask. The
mask cuts of the most significant bits in the integer, and dramatically lowers its space, making it suitable to be
passed as an index for a preallocated C array, ``arBuckets``. The mask is calculated as being the size of the HashTable
minus one. Here is the code for string typed keys::

    ht->nTableMask = ht->nTableSize - 1;
    void *p;

    h = zend_inline_hash_func(arKey, nKeyLength); /* Hash the arKey (char*) to get the hash key h (ulong) */

    nIndex = h & ht->nTableMask; /* Narrow h by masking its highest bits, obtain nIndex, an ulong from 0 to TableSize */

    p = ht->arBuckets[nIndex]; /* Use the nIndex to get back p (Bucket*) from the bucket array arBuckets */
    /* Use p here */

We said that if the provided key is of type integer (``ulong``) and not string (``char *``), we just don't need to run
the hash function. Code then becomes::

    ht->nTableMask = ht->nTableSize - 1;
    void *p;

    h = provided_key /* of type ulong */

    nIndex = h & ht->nTableMask; /* Narrow h by masking its highest bits, obtain nIndex, a ulong from 0 to TableSize */

    p = ht->arBuckets[nIndex]; /* Use the nIndex to get back p (Bucket*) from the bucket array arBuckets */
    /* Use p here */

What this means is that if you build a special PHP array, with only integer keys, that when used with the mask give
always the same index, then you will overcollide the array, and end-up having a possibly too huge linked list.
Traversing a linked list is O(n), so the more the linked list grows, the slower it becomes to traverse it. Knowing that the
API has to traverse the lists at every lookup or insertion (which triggers a lookup) in the table, it is then easy to
DOS this part of PHP.

To show this, let's build a use case and explain it:

.. code-block:: php

    <?php
    /* 2^15, for example, any power of 2 works */
    $size = 32768;
    $startTime = microtime(1);

    $array     = array();
    $maxInsert = $size * $size;

    for ($key = 0; $key <= $maxInsert; $key += $size) {
        $array[$key] = 0;
    }

    printf("%d inserts in %.2f seconds", $key/$size, microtime(1)-$startTime);

Running this code, you should obtain something like 32769 insertions in 9.84 seconds, which is just a very huge amount
of time. Let's now explain what happens at a lower level. We know that using a key as an integer, no hashing function
comes to play, so the code being run to compute the C array key (``nIndex``) mainly looks like::

    nIndex = h & ht->nTableMask; /* masking */
    p = ht->arBuckets[nIndex];

We know that ``nTableMask`` is table size minus one. As the key is added 32768 (2 powered by 15) at each step of the for
loop, it jumps from bit to bit, and the mask is just irrelevant:

.. code-block:: none

    for ($key = 0; $key <= $maxInsert; $key += $taille) {
        $array[$key] = 0;
    }

    mask:   0000.0111.1111.1111.1111
                     &
    32768   0000.1000.0000.0000.0000
    65536   0001.0000.0000.0000.0000
    98304   0001.1000.0000.0000.0000
    131072  0010.0000.0000.0000.0000
    163840  0010.1000.0000.0000.0000
    ...
                 = 0 !

We end up inserting every item (we insert 32769 total items) at the same ``arBuckets`` index: 0. Every item is then
added to the linked list sitting at index 0 of ``arBuckets``, and traversing a fast growing linked list takes so much
time. Be convinced by breaking this actual collision-proof code, just use a size of 32767 for example, instead of the
special 32768. You will get something like 32768 inserts in 0.01 seconds, which is about 1000 times faster.

When the hash algorithm + the hash mask works normally, meaning we are not cheating them voluntary like we did, it
distributes pretty well buckets into the ``arBuckets``:

.. image:: ./images/hash_distribution_ok.png

When it's not the case, you end with something like this, which we could call the 'worst scenario':

.. image:: ./images/hash_distribution_ko.png