# How to join a table and a table using ksqlDB

## Objective

Create a table-table join.

ksqlDB supports primary-key (1:1) as well as foreign-key (1:N) joins between tables. Many-to-many (N:M) joins are not supported currently. For a foreign-key join, you can use any left table column in the join condition to join it with the primary-key of the right table.

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Resources
https://docs.ksqldb.io/en/latest/developer-guide/joins/join-streams-and-tables/#table-table-joins
