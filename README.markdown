[![Build Status](https://travis-ci.org/atombender/multidb.png?branch=master)](https://travis-ci.org/atombender/multidb)

# Multidb

A simple, no-nonsense ActiveRecord extension which allows the application to switch between multiple database connections, such as in a primary/replica environment. For example:

    Multidb.use(:replica) do
      @posts = Post.all
    end

The extension was developed in order to support PostgreSQL 9.0's new hot standby support in a production environment.

Randomized balancing of multiple connections within a group is supported. In the future, some kind of automatic balancing of read/write queries could be implemented.

## Requirements

* Ruby 2.2 or later.
* ActiveRecord 4.0 or later. (Earlier versions can use the gem version 0.1.13 for Rails 3.2 and 0.1.10 for older version)

## Comparison to other ActiveRecord extensions

Compared to other, more full-featured extensions such as Octopus and Seamless Database Pool:

**Minimal amount of monkeypatching magic**. The only part of ActiveRecord that is overridden is `ActiveRecord::Base#connection`.

**Non-invasive**. Very small amounts of configuration and changes to the client application are required.

**Orthogonal**. Unlike Octopus, for example, connections follow context:

    Multidb.use(:primary) do
      @post = Post.find(1)
      Multidb.use(:replica) do
        @post.authors  # This will use the replica
      end
    end

**Low-overhead**. Since `connection` is called on every single database operation, it needs to be fast. Which it is: Multidb's implementation of
`connection` incurs only a single hash lookup in `Thread.current`.

However, Multidb also has fewer features. At the moment it will _not_ automatically split reads and writes between database backends.

## Getting started

Add to your `Gemfile`:

    gem 'ar-multidb', :require => 'multidb'

All that is needed is to set up your `database.yml` file:

    production:
      adapter: postgresql
      database: myapp_production
      username: ohoh
      password: mymy
      host: db1
      multidb:
        databases:
          replica:
            host: db-replica

Each database entry may be a hash or an array. So this also works:

    production:
      adapter: postgresql
      database: myapp_production
      username: ohoh
      password: mymy
      host: db1
      multidb:
        databases:
          replica:
            - host: db-replica1
            - host: db-replica2

If multiple elements are specified, Multidb will use the list to pick a random candidate connection.

The database hashes follow the same format as the top-level adapter configuration. In other words, each database connection may override the adapter, database name, username and so on.

To use the connection, modify your code by wrapping database access logic in blocks:

    Multidb.use(:replica) do
      @posts = Post.all
    end

To wrap entire controller requests, for example:

    class PostsController < ApplicationController
      around_filter :run_using_replica, only: [:index]

      def index
        @posts = Post.all
      end

      def edit
        # Won't be wrapped
      end

      def run_using_replica(&block)
        Multidb.use(:replica, &block)
      end
    end

You can also set the current connection for the remainder of the thread's execution:

    Multidb.use(:replica)
    # Do work
    Multidb.use(:primary)

Note that the symbol `:default` will (unless you override it) refer to the default top-level ActiveRecord configuration.

## Development mode

In development you will typically want `Multidb.use(:replica)` to still work, but you probably don't want to run multiple databases on your development box. To make `use` silently fall back to using the default connection, Multidb can run in fallback mode.

If you are using Rails, this will be automatically enabled in `development` and `test` environments. Otherwise, simply set `fallback: true` in `database.yml`:

    development:
      adapter: postgresql
      database: myapp_development
      username: ohoh
      password: mymy
      host: db1
      multidb:
        fallback: true

## SQL Caching

To use [SQL Caching](https://guides.rubyonrails.org/caching_with_rails.html#sql-caching) (per request in memory caching of queries), add the `query_cache: true`. If you add it at the same level as the `multidb:` entry, then all multidb connections use SQL Caching. If you add it to specific `databases:` entries under `multidb:`, then SQL Caching is turned on only for those entries.

    production:
      adapter: postgresql
      database: myapp_production
      username: ohoh
      password: mymy
      host: db1
      multidb:
        databases:
          replica:
            host: db-replica
            query_cache:true
          other:
            host: db-other

The above example would turn on SQL Caching for this example:

    Multidb.use(:replica) do
      @posts = Post.all
    end

But not for this example:

    Multidb.use(:other) do
      @comments = Comments.all
    end

## Limitations

Multidb does not support per-class connections (eg., calling `establish_connection` within a class, as opposed to `ActiveRecord::Base`).

## Legal

Copyright (c) 2011-2014 Alexander Staubo. Released under the MIT license. See the file `LICENSE`.
