\if :{?util_jtd_sql}
\else
\set util_jtd_sql true

create schema if not exists util;

-- for composite-type, table
-- https://www.postgresql.org/docs/current/catalog-pg-attribute.html
--
create or replace function util.to_jtd (
    cls regclass,
    propertiesKey text default 'properties' -- or optionalProperties
)
    returns jsonb
    security definer
    language sql
    stable
as $$
    select jsonb_build_object(
        propertiesKey,
        jsonb_object_agg (
            a.attname,

            -- build property type/nullable
            --
            util.to_jtd (
                a.atttypid::oid,
                propertiesKey
            )
            || jsonb_build_object (
                'nullable',
                not a.attnotnull)
        )
    )
    from pg_attribute a
    where a.attrelid::regclass = cls
    and attnum>0
$$;


-- for a type, based on typcategory
-- https://www.postgresql.org/docs/current/catalog-pg-type.html#CATALOG-TYPCATEGORY-TABLE
--
--
create or replace function util.to_jtd (
    id oid,
    propertiesKey text default 'properties' -- or optionalProperties
)
    returns jsonb
    security definer
    language sql
    stable
as $$
    select case
    when typcategory='S' then '{"type":"string"}'
    when typcategory='B' then '{"type":"boolean"}'
    when typcategory='D' then '{"type":"timestamp"}'

    -- numeric-type (for now to float64)
    when typcategory='N' then '{"type":"float64"}'

    -- composite
    when typcategory='C' then
        util.to_jtd(
            t.typrelid::regclass,
            propertiesKey)

    -- array
    when typcategory='A' then
        jsonb_build_object(
            'elements',
            util.to_jtd(t.typelem, propertiesKey))

    -- enum
    when typcategory='E' then
        jsonb_build_object(
            'enum',
            (select array_agg(enumlabel)
            from (
                select enumlabel
                from pg_enum
                where enumtypid = t.oid
                order by enumsortorder
            ) tab)
        )

    -- json/jsonb
    when typname='json' or typname='jsonb' then
        '{}'

    -- default
    else '{"type":"string"}'
    end

    from pg_type t
    where oid=id
$$;

create or replace function util.to_jtd (
    cls text,
    propertiesKey text default 'properties'
)
    returns jsonb
    security definer
    language sql
    stable
as $$
    select util.to_jtd(
        cls::regtype,
        propertiesKey)
$$;


\if :test
    create type tests.my_enum as enum (
        'a', 'b', 'x', 'y'
    );

    create type tests.my_type as (
        x int,
        s text
    );

    create table tests.my_table (
        a int,
        b tests.my_type[],
        c tests.my_enum,
        d jsonb
    );

    create function tests.test_util_jtd ()
        returns setof text
        language plpgsql
    as $$
    declare
        a jsonb;
    begin
        a = util.to_jtd(null);
        return next ok(a is null, 'null-check');

        a = util.to_jtd('text');
        return next ok(a->>'type' = 'string', 'handles text');

        a = util.to_jtd('bigint');
        return next ok(a->>'type' = 'float64', 'handles numeric/number as float64');

        a = util.to_jtd('tests.my_enum');
        return next ok(a->'enum' = '["a","b","x","y"]'::jsonb, 'handles enum');

        a = util.to_jtd('numeric[]');
        return next ok(a->'elements'->>'type' = 'float64', 'handles array');

        a = util.to_jtd('tests.my_type');
        return next ok(
            a->'properties'->'x'->>'type' = 'float64'
            and
            a->'properties'->'s'->>'type' = 'string'
        , 'handles composite type');

        a = util.to_jtd('tests.my_table');
        return next ok(
            a->'properties'->'a'->>'type' = 'float64'
            and
            a->'properties'->'b'->'elements'->'properties'->'x'->>'type' = 'float64'
            and
            a->'properties'->'c'->'enum' = '["a","b","x","y"]'::jsonb
        , 'handles complex type');

    end;
    $$;
\endif

\endif