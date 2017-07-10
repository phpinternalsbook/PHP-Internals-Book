Declaring and using INI settings
================================

This chapter details how PHP plays with its configuration and how an extension is expected to hook into the main 
configuration step of PHP, by registering and making use of INI settings.

Reminders on INI settings
-------------------------

Before going further, you must remember how INI settings and PHP configuration work in PHP. Here are the steps, once 
more extracted as an interpretation of the source code. PHP INI file parsing steps happen in 
`php_init_config() <https://github.com/php/php-src/blob/4903f044d3a65de5b1c457d9eb618c9e247f7086/main/php_ini.c#L382>`_, 
and everything related to INI mainly takes place in 
`Zend/zend_ini.c <https://github.com/php/php-src/blob/4903f044d3a65de5b1c457d9eb618c9e247f7086/Zend/zend_ini.c>`_.

First, PHP tries to parse one or several INI files. Those files may declare some settings, that may or may not be 
relevant in the future. At this very early stage (INI files parsing), PHP knows nothing about what to expect in such 
files. It just parses the content, and saves this one for later use.

Then as a second step, PHP boots up its extensions, calling their ``MINIT()``. If you need to remember about the PHP 
lifecycle, :doc:`read the dedicated chapter <php_lifecycle>`. ``MINIT()`` may now register the current 
extension INI settings of interest. When registering the setting, the engine checks if it parsed its definition before, 
as part of the INI files parsing step. If that was the case, then the INI setting is registered into the engine and it 
gets the value that was parsed from INI files. If it had no definition in INI files parsed, then it gets registered with 
the default value the extension designer gives to the API.

.. note:: The default value the setting will get is probed from INI files parsing. If none is found, then the default 
          is the one given by the extension developer, not the other way around.

The default value we are talking about here is called the **"master value"**. You may recall it from a ``phpinfo()`` 
output, right ?:

.. image:: ./images/php_extensions_ini.png
   :align: center
   
The master value cannot change. If during a request, the user wants to change the configuration, f.e using 
``ini_set()``, and if he's allowed to, then the changed value will be the **"local value"** , that is the current value 
for the current request. The engine will automaticaly restore the local value to the master value value at the end of 
the request.

``ini_get()`` reads the current request-bound local value, whereas ``get_cfg_var()`` will read the master value 
whatever happens.

.. note:: If you have understood correctly, ``get_cfg_var()`` will return false for any value asked that was not part of 
          INI file parsing, even if the value exists and was declared by an extension.
          And the opposite is true: ``ini_get()`` will return false if asked for a setting that no extension has declared 
          interest in, even if such a setting was part of an INI file parsing (like php.ini).

Zoom on INI settings
--------------------

Into the engine, an INI setting is represented by a ``zend_ini_entry`` structure::

    struct _zend_ini_entry {
        zend_string *name;
        int (*on_modify)(zend_ini_entry *entry, zend_string *new_value, void *mh_arg1, void *mh_arg2, void *mh_arg3,
                         int stage);
        void *mh_arg1;
        void *mh_arg2;
        void *mh_arg3;
        zend_string *value;
        zend_string *orig_value;
        void (*displayer)(zend_ini_entry *ini_entry, int type);
        int modifiable;

        int orig_modifiable;
        int modified;
        int module_number;
    };

Nothing really strong in such a structure. Setting's ``name`` and ``value`` are the most commonly used fields. Note 
however that the value is a string (as :doc:`zend_string <../internal_types/strings/zend_strings>`) and nothing else.
Then, like we detailed in the introduction chapter above, we find the ``orig_value``, ``orig_modified``, ``modifiable`` 
and ``modified`` fields which are related to the modification of the setting's value. The setting must keep in memory 
its original value (as "master value"). ``modifiable`` tells if the setting is actually modifable, and must have one of 
the values you should be aware of from PHP userland : ``ZEND_INI_USER``, ``ZEND_INI_PERDIR``, ``ZEND_INI_SYSTEM`` or 
``ZEND_INI_ALL``.

Then come two handlers: ``on_modify()`` is called whenever the current setting's value is modified, like f.e using a call 
to ``ini_set()`` (but not only). We'll focus deeper on ``on_modify()`` later, but think of it as being a 
*validator function* (f.e if the setting is expected to represent an integer, you may validate the values you'll be 
given against integers). It also serve as a memory bridge to update global values, we'll get back on that later as well.

``diplayer()`` is less useful, and you usually don't pass any. ``displayer()`` is about how to display your setting. 
F.e, you may remember that PHP tend to display *On* for boolean values of *true*/*yes*/*on*/*1* etc. That's the 
``displayer()`` job.

You will also need to deal with this structure ``zend_ini_entry_def``::

    typedef struct _zend_ini_entry_def {
        const char *name;
        ZEND_INI_MH((*on_modify));
        void *mh_arg1;
        void *mh_arg2;
        void *mh_arg3;
        const char *value;
        void (*displayer)(zend_ini_entry *ini_entry, int type);
        int modifiable;

        uint name_length;
        uint value_length;
    } zend_ini_entry_def;

Pretty much similar to ``zend_ini_entry``, ``zend_ini_entry_def`` is used by the programmer (you) when he must register 
an INI setting against the engine. The engine reads a ``zend_ini_entry_def``, and creates internally a 
``zend_ini_entry`` for its own usage, based on the definition model you provide. Easy.

Registering INI entries
-----------------------

INI settings are persistent through requests. They can change their value during a request (runtime), but they'll go back 
to original value at request shutdown. Thus, registering INI settings is done once for all, in ``MINIT()`` hook of your 
extension.

What you must do is declare a vector of ``zend_ini_entry_def``, you'll be helped with dedicated macros for that. Then, 
you register your vector against the engine and you are done for the declaration. Let's see that::




