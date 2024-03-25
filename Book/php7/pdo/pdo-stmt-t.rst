.. _pdo_stmt_t:

pdo_stmt_t definition
=====================

All fields should be treated as read-only unless explicitly stated
otherwise.

.. code-block:: c

    /* represents a prepared statement */
    struct _pdo_stmt_t {
        /* driver specifics */
        struct pdo_stmt_methods *methods;

The driver *must* set this during
``SKEL_handle_preparer``.

.. code-block:: c

        void *driver_data;

This item is for use by the driver; the intended usage is to store a
pointer (during ``SKEL_handle_factory``) 
to whatever instance data is required to maintain a connection to
the database.

.. code-block:: c

        /* if true, we've already successfully executed this statement at least
         * once */
        unsigned executed:1;

This is set by PDO after the statement has been executed for the first
time.  Your driver can inspect this value to determine if it can skip
one-time actions as an optimization.

.. code-block:: c

        /* if true, the statement supports placeholders and can implement
         * bindParam() for its prepared statements, if false, PDO should
         * emulate prepare and bind on its behalf */
        unsigned supports_placeholders:2;

Discussed in more detail in :ref:`pdo_preparer`.

.. code-block:: c

        /* the number of columns in the result set; not valid until after
         * the statement has been executed at least once.  In some cases, might
         * not be valid until fetch (at the driver level) has been called at least once. */
        int column_count;

Your driver is responsible for setting this field to the number of
columns available in a result set.  This is usually set during
``SKEL_stmt_execute`` but with some database
implementations, the column count may not be available until
``SKEL_stmt_fetch`` has been called at least once.
Drivers that implement ``SKEL_stmt_next_rowset`` should
update the column count when a new rowset is available.

.. code-block:: c

        struct pdo_column_data *columns;

PDO will allocate this field based on the value that you set for the
column count.  You are responsible for populating each column during
``SKEL_stmt_describe``.  You must set the
``precision``, ``maxlen``,
``name``, ``namelen`` and
``param_type`` members for each column.
The ``name`` is expected to be allocated using
``emalloc``; PDO will call ``efree`` at
the appropriate time.

.. code-block:: c

        /* points at the dbh that this statement was prepared on */
        pdo_dbh_t *dbh;

        /* keep track of bound input parameters.  Some drivers support
         * input/output parameters, but you can't rely on that working */
        HashTable *bound_params;
        /* When rewriting from named to positional, this maps positions to names */
        HashTable *bound_param_map; 
        /* keep track of PHP variables bound to named (or positional) columns
         * in the result set */
        HashTable *bound_columns;

        /* not always meaningful */
        long row_count;

        /* used to hold the statement's current query */
        char *query_string;
        int query_stringlen;

        /* the copy of the query with expanded binds ONLY for emulated-prepare drivers */
        char *active_query_string;
        int active_query_stringlen;

        /* the cursor specific error code. */
        pdo_error_type error_code;

        /* used by the query parser for driver specific
         * parameter naming (see pgsql driver for example) */
        const char *named_rewrite_template;
    };
