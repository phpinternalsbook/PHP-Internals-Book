Strings management: zend_string
===============================

Any program needs to manage strings. Here, we'll detail a custom solution that fits PHP needs : ``zend_string``.
Every time PHP needs to work with a string, a ``zend_string`` structure will be used. This structure is just a simple
thin wrapper over the ``char *`` string type of the C language.

It adds memory management facilities, so that a same string can be shared in several places without the need to
duplicate it. Also, some strings are "interned", that is they are "persistent" allocated and specially managed by the
memory manager so that they don't get destroyed across several requests. Those later get a permanent allocation from
:doc:`Zend Memory Manager <../../memory_management/zend_memory_manager>`.

Structure and access macros
---------------------------

Here is the simple ``zend_string`` structure exposed::

    struct _zend_string {
        zend_refcounted_h gc;
        zend_ulong        h;
        size_t            len;
        char              val[1];
    };

Like you can see, the structure embeds a ``zend_refcounted_h`` header. This is done for memory management and reference.
As the string is very likely to be used as the key of a HashTable probe, it embeds its hash in the ``h`` field. This is
an unsigned long ``zend_ulong``. This number is only used when the ``zend_string`` needs to be hashed, especially
when used together with :doc:`../hashtables`; this is very likely though.

As you know, the string knows its length as the ``len`` field, to support "binary strings". Binary strings are
strings that embed one or several ``NUL`` characters (\\0). When passed to libc functions, those strings will get
truncated or their length won't be computed the right way. So in ``zend_string``, the length of the string is always
known. Please, note that the length computes the number of ASCII chars (bytes) not counting the terminating ``NUL``, but
counting the eventual middle NULs. For example, the string "foo" is stored as "foo\\0" in a ``zend_string`` and its
length is then 3. Also, the string "foo\\0bar" will be stored as "foo\\0bar\\0" and the length will be 7.

Finally, the characters are stored into the ``char[1]`` field. This is not a ``char *``, but a ``char[1]``. Why that?
This is a memory optimization known as "C struct hack" (you may use a search engine with these terms). Basically, that
allows the engine to allocate space for the ``zend_string`` structure and the characters to be stored, as one solo C
pointer. This optimizes memory accesses as memory will be a contiguous allocated block, and not two blocks far away from each other in
memory (one for ``zend_string *``, and one for the ``char *`` to store into it).

This struct hack must be remembered, as the memory layout looks like with the C chars at the end of the C ``zend_string``
structure, and may be felt/seen when using a C debugger (or when debugging strings). This hack is entirely managed by
the API you'll use when manipulating ``zend_string`` structures.

.. image:: images/zend_string_memory_layout.png
   :align: center

Using zend_string API
---------------------

Simple use case
***************

Like with :doc:`../zvals`, you don't manipulate the ``zend_string`` internals fields by hand, but always use macros
for that. There also exists macros to trigger actions on strings. Those are not functions but macros, all stored into
the required `Zend/zend_string.h <https://github.com/php/php-src/blob/PHP-7.0/Zend/zend_string.h>`_ header::

    zend_string *str;

    str = zend_string_init("foo", strlen("foo"), 0);
    php_printf("This is my string: %s\n", ZSTR_VAL(str));
    php_printf("It is %zd char long\n", ZSTR_LEN(str));

    zend_string_release(str);

The above simple example show you basic string management. The ``zend_string_init()`` function (which in fact is a macro,
but let's pass such details) should be given your full C string as a ``char *``, and its length. The last parameter- of
type int- should be 0 or 1.
If you pass 0, you ask the engine to use a request-bound heap allocation using the Zend Memory Manager. Such allocation
will be destroyed at the end of the current request. If you don't do it yourself, on a debug build, the engine will
shout at you about a memory leak you just created.
If you pass 1, you ask for what we called a "persistent" allocation, that is the engine will use a traditional C
``malloc()`` call and will not track the memory allocation in any way.

.. note:: If you need more information about memory management, you may read the :doc:`dedicated chapter
          <../../memory_management>`.

Then, we display the string. We access the character array by using the ``ZSTR_VAL()`` macro. ``ZSTR_LEN()`` allows
access to the length information. ``zend_string`` related macros all start with ``ZSTR_**()``, beware that is not the
same as ``Z_STR**()`` macros.

.. note:: The length is stored using a ``size_t`` type. Hence, to display it, *"%zd"* is necessary for ``printf()``. You
          should always use the right ``printf()`` formats. Failing to do that can crash the application or create
          security issues. For a nice recall on ``printf()`` formats, please visit
          `this link <http://www.cplusplus.com/reference/cstdio/printf/>`_

Finally, we release the string using ``zend_string_release()``. This release is mandatory. This is about memory management.
The "releasing" is a simple operation : decrement the reference counter of the string, if it falls to zero, the API will
free the string for you. If you forget to release a string, you will very likely create a memory leak.

.. note:: You must always think about memory management in C. If you allocate - whether directly using ``malloc()``, or
          using an API that will do it for you - you must ``free()`` at some point. Failing to do that will create memory
          leaks and translate into a badly designed program that nobody will be able to use safely.

Playing with the hash
*********************

If you need to access the hash, use ``ZSTR_H()``. However, the hash is not computed automatically when you create your
``zend_string``. It will be done for you however when using that string with the HashTable API.
If you want to force the hash to get computed now, use ``ZSTR_HASH()`` or ``zend_string_hash_val()``.
Once the hash is computed, it is saved and never computed again. If for any reason, you need to recompute it - f.e
because you changed the value of the string - use ``zend_string_forget_hash_val()``::

    zend_string *str;

    str = zend_string_init("foo", strlen("foo"), 0);
    php_printf("This is my string: %s\n", ZSTR_VAL(str));
    php_printf("It is %zd char long\n", ZSTR_LEN(str));

    zend_string_hash_val(str);
    php_printf("The string hash is %lu\n", ZSTR_H(str));

    zend_string_forget_hash_val(str);
    php_printf("The string hash is now cleared back to 0!");

    zend_string_release(str);

String copy and memory management
*********************************

One very nice feature of ``zend_string`` API is that it allows one part to "own" a string by simply declaring interest
with it. The engine will then not duplicate the string in memory, but simply increment its refcount
(as part of its ``zend_refcounted_h``). This allows sharing a single piece of memory in many places into the code.

That way, when we talk about "copying" a ``zend_string``, in fact we don't copy anything in memory. If needed- that is
still a possible operation- we then talk about "duplicating" the string. Here we go::

    zend_string *foo, *bar, *bar2, *baz;

    foo = zend_string_init("foo", strlen("foo"), 0); /* creates the "foo" string in foo */
    bar = zend_string_init("bar", strlen("bar"), 0); /* creates the "bar" string in bar */

    /* creates bar2 and shares the "bar" string from bar into bar2.
       Also increments the refcount of the "bar" string to 2 */
    bar2 = zend_string_copy(bar);

    php_printf("We just copied two strings\n");
    php_printf("See : bar content : %s, bar2 content : %s\n", ZSTR_VAL(bar), ZSTR_VAL(bar2));

    /* Duplicate in memory the "bar" string, create the baz variable and
       make it solo owner of the newly created "bar" string */
    baz = zend_string_dup(bar, 0);

    php_printf("We just duplicated 'bar' in 'baz'\n");
    php_printf("Now we are free to change 'baz' without fearing to change 'bar'\n");

    /* Change the last char of the second "bar" string
       turning it to "baz" */
    ZSTR_VAL(baz)[ZSTR_LEN(baz) - 1] = 'z';

    /* Forget the old hash (if computed) as now the string changed, thus
       its hash must also change and get recomputed */
    zend_string_forget_hash_val(baz);

    php_printf("'baz' content is now %s\n", ZSTR_VAL(baz));

    zend_string_release(foo);  /* destroys (frees) the "foo" string */
    zend_string_release(bar);  /* decrements the refcount of the "bar" string to one */
    zend_string_release(bar2); /* destroys (frees) the "bar" string both in bar and bar2 vars */
    zend_string_release(baz);  /* destroys (frees) the "baz" string */

We start by just allocating "foo" and "bar". Then we create the ``bar2`` string as being a copy of ``bar``. Here, everybody
must remember : ``bar`` and ``bar2`` point to *the same* C string in memory, and changing one will change the second
one. This is ``zend_string_copy()`` behavior : it just increments the refcount of the owned C string.

If we want to separate the strings- aka we want to have two different copies of that string in memory -we need to
duplicate using ``zend_string_dup()``. We then duplicate ``bar2`` variable string into the ``baz`` variable. Now, the
``baz`` variable embeds its own copy of the string, and can change it without impacting ``bar2``. That is what we do :
we change the final 'r' in 'bar' with a 'z', for 'baz'. And then we display it, and free memory of every string.

Note that we forgot the hash value (if it were computed before, no need to think about that detail). This is a good
practice to remember about. Like we already said, the hash is used if the ``zend_string`` is used as part of HashTables.
This is a very common operation in development, and changing a string value requires to recompute the hash value as
well. Forgetting such a step will lead to bugs that could cost some time to track.

String operations
*****************

The ``zend_string`` API allows other operations, such as extending or shrinking strings, changing their case or comparing
them. There is no concat operation available yet, but that is pretty easy to perform::

    zend_string *FOO, *bar, *foobar, *foo_lc;

    FOO = zend_string_init("FOO", strlen("FOO"), 0);
    bar = zend_string_init("bar", strlen("bar"), 0);

    /* Compares a zend_string against a C string literal */
    if (!zend_string_equals_literal(FOO, "foobar")) {
        foobar = zend_string_copy(FOO);

        /* realloc()ates the C string to a larger buffer */
        foobar = zend_string_extend(foobar, strlen("foobar"), 0);

        /* concatenates "bar" after the newly reallocated large enough "FOO" */
        memcpy(ZSTR_VAL(foobar) + ZSTR_LEN(FOO), ZSTR_VAL(bar), ZSTR_LEN(bar));
    }

    php_printf("This is my new string: %s\n", ZSTR_VAL(foobar));

    /* Compares two zend_string together */
    if (!zend_string_equals(FOO, foobar)) {
        /* duplicates a string and lowers it */
        foo_lc = zend_string_tolower(FOO);
    }

    php_printf("This is FOO in lower-case: %s\n", ZSTR_VAL(foo_lc));

    /* frees memory */
    zend_string_release(FOO);
    zend_string_release(bar);
    zend_string_release(foobar);
    zend_string_release(foo_lc);

zend_string access with zvals
*****************************

Now that you know how to manage and manipulate ``zend_string``, let's see the interaction they got with the ``zval``
container.

.. note:: You need to be familiar with zvals, if not, read the :doc:`../zvals` dedicated chapter.

The macros will allow you to store a ``zend_string`` into a ``zval``, or to read the ``zend_string`` from a ``zval``::

    zval myval;
    zend_string *hello, *world;

    hello = zend_string_init("hello", strlen("hello"), 0);

    /* Stores the string into the zval */
    ZVAL_STR(&myval, hello);

    /* Reads the C string, from the zend_string from the zval */
    php_printf("The string is %s", Z_STRVAL(myval));

    world = zend_string_init("world", strlen("world"), 0);

    /* Changes the zend_string into myval : replaces it with another one */
    Z_STR(myval) = world;

    /* ... */

What you must memorize is that every macro beginning by ``ZSTR_***(s)`` will act on a ``zend_string``.

* ``ZSTR_VAL()``
* ``ZSTR_LEN()``
* ``ZSTR_HASH()``
* ...

Every macro beginning by ``Z_STR**(z)`` will act on a ``zend_string`` itself embedded into a ``zval``

* ``Z_STRVAL()``
* ``Z_STRLEN()``
* ``Z_STRHASH()``
* ...

A few other that you won't probably need also exist.

PHP's history and classical C strings
*************************************

Just a quick note about classical C strings. In C, strings are character arrays (``char foo[]``), or pointers to
characters (``char *``). They don't know anything about their length, that's why they are NULL terminated (knowing the
beginning of the string and its end, you know its length).

Before PHP 7, ``zend_string`` structure simply did not exist. A traditional ``char * / int`` couple were used back in
that time. You may still find rare places into PHP source where ``char * / int`` couple is used instead of
``zend_string``. You may also find API facilities to interact between a ``zend_string`` on one side, and a
``char * / int`` couple on the other side.

Wherever it is possible : make use of ``zend_string``. Some rare places don't make use of ``zend_string`` because it
is not relevant at that place to use them, but you'll find lots of reference to ``zend_string`` anyway in PHP source
code.

Interned zend_string
********************

Just a quick word here about `interned strings <https://en.wikipedia.org/wiki/String_interning>`_. You could 
need such a concept in extension development. Interned strings also interact with OPCache extension.

Interned strings are deduplicated strings. When used with OPCache, they also get reused from request to request.

Say you want to create the string "foo". What you tend to do is simply create a new string "foo"::

    zend_string *foo;
    foo = zend_string_init("foo", strlen("foo"), 0);

    /* ... */

But a question arises : Hasn't that piece of string already been created before you need it?
When you need a string, you code is executed at some point in PHP's life, that means that some piece of code happening
before yours may have needed the exact same piece of string ("foo" for our example).

Interned strings is about asking the engine to probe the interned strings store, and reuse the already allocated pointer
if it could find your string. If not : create a new string and "intern" it, that is make it available to other parts
of PHP source code (other extensions, the engine itself, etc...).

Here is an example::

    zend_string *foo;
    foo = zend_string_init("foo", strlen("foo"), 0);

    foo = zend_new_interned_string(foo);

    php_printf("This string is interned : %s", ZSTR_VAL(foo));

    zend_string_release(foo);

What we do in the code above, is we create a new ``zend_string`` very classically. Then, we pass that created
``zend_string`` to ``zend_new_interned_string()``. This function looks for the same piece of string ("foo" here) into
the engine interned string buffer. If it finds it (meaning someone already created such a string), it then releases
your string (probably freeing it) and replaces it with the string from the interned string buffer. If it does not find it:
it adds it to the interned string buffer and so makes it available for future usage or other parts of PHP.

You must take care about memory allocation. Interned strings always have a refcount set to one, because they don't need
to be refcounted, as they will get shared with the interned strings buffer, and thus they can't be destroyed out of it.

Example::

    zend_string *foo, *foo2;

    foo  = zend_string_init("foo", strlen("foo"), 0);
    foo2 = zend_string_copy(foo); /* increments refcount of foo */

     /* foo points to the interned string buffer, and refcount
      * in original zend_string falls back to 1 */
    foo = zend_new_interned_string(foo);

    /* This doesn't do anything, as foo is interned */
    zend_string_release(foo);

    /* The original buffer referenced by foo2 is released */
    zend_string_release(foo2);

    /* At the end of the process, PHP will purge its interned
      string buffer, and thus free() our "foo" string itself */

It's all about garbage collection.

When a string is interned, its GC flags are changed to add the ``IS_STR_INTERNED`` flag, whatever the memory allocation
class they use (permanent or request based).
This flag is probed when you want to copy or release a string. If the string is interned, the engine does not increment
its refcount as you copy the string. But it doesn't decrement it nor free it if you release the string. It shadowly
does nothing. At the end of the process lifetime, it will destroy its interned strings buffer, and it will free your
interned strings.

This process is in fact a little bit more complex than this. If you make use of an interned string out of a 
:doc:`request processing <../../extensions_design/php_lifecycle>`, that string will be interned for sure.
However, if you make use of an interned string as PHP is treating a request, then this string will only get interned for 
the current request, and will get cleared after that.
All this is valid if you don't use the OPCache extension, something you shouldn't do : use it.

When using the OPCache extension, if you make use of an interned string out of a 
:doc:`request processing <../../extensions_design/php_lifecycle>`, that string will be 
interned for sure and will also be shared to every PHP process or thread that will be spawned by you parallelism layer.
Also, if you make use of an interned string as PHP is treating a request, this string will also get interned by OPCache 
itself, and shared to every PHP process or thread that will be spawned by you parallelism layer.

Interned strings mechanisms are then changed when OPCache extension fires in. OPCache not only allows to intern strings 
that come from a request, but it also allows to share them to every PHP process of the same pool. This is done using 
shared memory. When saving an interned string, OPCache will also add the ``IS_STR_PERMANENT`` flag to its GC info. 
That flag means the memory allocation used for the structure (``zend_string`` here) is permanent, it could be a shared 
read-only memory segment.

Interned strings save memory, because the same string is never stored more than once in memory. But it could waste some
CPU time as it often needs to lookup the interned strings store, even if that process is well optimized yet.
As an extension designer, here are global rules:

* If OPCache is used (it should be), and if you need to create read-only strings : use an interned string.
* If you need a string you know for sure PHP will have interned (a well-known-PHP-string, f.e "php" or "str_replace"),
  use an interned string.
* If the string is not read-only and could/should be altered after its been created, do not use an interned string.
* If the string is unlikely to be reused in the future, do not use an interned string.

.. warning:: Never ever try to modify (write to) an interned string, you'll likely crash.

Interned strings are detailed in `Zend/zend_string.c <https://github.com/php/php-src/blob/PHP-7.0/Zend/zend_string.c>`_
