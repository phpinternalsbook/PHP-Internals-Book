Streams Structures
------------------

.. _php_stream_statbuf:

php_stream_statbuf
^^^^^^^^^^^^^^^^^^

Holds information about a file or URL::

    typedef struct _php_stream_statbuf {
        struct stat sb;
    } php_stream_statbuf;

``sb`` is a regular, system defined, struct stat.

.. _php_stream_dirent:

php_stream_dirent
^^^^^^^^^^^^^^^^^

Holds information about a single file during dir scanning::

    typedef struct _php_stream_dirent {
        char d_name[MAXPATHLEN]
    } php_stream_dirent;

``d_name`` holds the name of the file, relative to the directory
being scanned.

php_stream_ops
^^^^^^^^^^^^^^

Holds member functions for a stream implementation::

    typedef struct _php_stream_ops {
        /* all streams MUST implement these operations */
        size_t (*write)(php_stream *stream, const char *buf, size_t count TSRMLS_DC);
        size_t (*read)(php_stream *stream, char *buf, size_t count TSRMLS_DC);
        int (*close)(php_stream *stream, int close_handle TSRMLS_DC);
        int (*flush)(php_stream *stream TSRMLS_DC);
        
        const char *label; /* name describing this class of stream */
        
        /* these operations are optional, and may be set to NULL if the stream does not
         * support a particular operation */
        int (*seek)(php_stream *stream, off_t offset, int whence TSRMLS_DC);
        char *(*gets)(php_stream *stream, char *buf, size_t size TSRMLS_DC);
        int (*cast)(php_stream *stream, int castas, void **ret TSRMLS_DC);
        int (*stat)(php_stream *stream, php_stream_statbuf *ssb TSRMLS_DC);
    } php_stream_ops;

php_stream_wrapper
^^^^^^^^^^^^^^^^^^

Holds wrapper properties and pointer to operations::

    typedef struct _php_stream_wrapper {
        php_stream_wrapper_ops *wops;   /* operations the wrapper can perform */
        void *abstract;                 /* context for the wrapper */
        int is_url;                     /* so that PG(allow_url_fopen) can be respected */

        /* support for wrappers to return (multiple) error messages to the stream opener */
        int err_count;
        char **err_stack;
    } php_stream_wrapper;

php_stream_wrapper_ops
^^^^^^^^^^^^^^^^^^^^^^

Holds member functions for a stream wrapper implementation::

    typedef struct _php_stream_wrapper_ops {
        /* open/create a wrapped stream */
        php_stream *(*stream_opener)(php_stream_wrapper *wrapper, char *filename, char *mode,
                int options, char **opened_path, php_stream_context *context STREAMS_DC TSRMLS_DC);
        /* close/destroy a wrapped stream */
        int (*stream_closer)(php_stream_wrapper *wrapper, php_stream *stream TSRMLS_DC);
        /* stat a wrapped stream */
        int (*stream_stat)(php_stream_wrapper *wrapper, php_stream *stream, php_stream_statbuf *ssb TSRMLS_DC);
        /* stat a URL */
        int (*url_stat)(php_stream_wrapper *wrapper, char *url, php_stream_statbuf *ssb TSRMLS_DC);
        /* open a "directory" stream */
        php_stream *(*dir_opener)(php_stream_wrapper *wrapper, char *filename, char *mode,
                int options, char **opened_path, php_stream_context *context STREAMS_DC TSRMLS_DC);

        const char *label;

        /* Delete/Unlink a file */
        int (*unlink)(php_stream_wrapper *wrapper, char *url, int options, php_stream_context *context TSRMLS_DC);
    } php_stream_wrapper_ops;

php_stream_filter
^^^^^^^^^^^^^^^^^

Holds filter properties and pointer to operations::

    typedef struct _php_stream_filter {
        php_stream_filter_ops *fops;
        void *abstract; /* for use by filter implementation */
        php_stream_filter *next;
        php_stream_filter *prev;
        int is_persistent;

        /* link into stream and chain */
        php_stream_filter_chain *chain;

        /* buffered buckets */
        php_stream_bucket_brigade buffer;
    } php_stream_filter;

php_stream_filter_ops
^^^^^^^^^^^^^^^^^^^^^

Holds member functions for a stream filter implementation::

    typedef struct _php_stream_filter_ops {
        php_stream_filter_status_t (*filter)(
            php_stream *stream,
            php_stream_filter *thisfilter,
            php_stream_bucket_brigade *buckets_in,
            php_stream_bucket_brigade *buckets_out,
            size_t *bytes_consumed,
            int flags
            TSRMLS_DC);

        void (*dtor)(php_stream_filter *thisfilter TSRMLS_DC);

        const char *label;
    } php_stream_filter_ops;
