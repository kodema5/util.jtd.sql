// deno test --allow-env --allow-net --unstable tests

import postgres from 'https://deno.land/x/postgresjs/mod.js'
import { assert } from "https://deno.land/std@0.152.0/testing/asserts.ts"
import Jtd from 'https://esm.sh/ajv@8.11.0/dist/jtd'

Deno.test('util.jtd', async (t) => {

    // set db
    const pg = postgres({
        database: 'web',
        username: 'web',
        password: 'rei',
        max: 10,
        onnotice: () => {},
    })
    await pg`
    do $$ begin
    drop schema if exists test_util_jtd cascade;
    create schema test_util_jtd;

    create type test_util_jtd.my_type as (
        a int,
        b text,
        c jsonb
    );
    end; $$;
    `

    // get jtd
    let jtd = new Jtd()
    let rs = await pg`
        select util.to_jtd('test_util_jtd.my_type') as my_type
    `
    let sch = rs[0].my_type

    jtd.addSchema(sch, 'my_type')
    let fn = jtd.getSchema('my_type')

    await t.step('test invalid', async () => {
        assert(!fn({a:1, b:2}))
        // console.log(fn.errors)
    })

    await t.step('test valid', async () => {
        assert(!fn({a:1, b:2, c:{a:123, b:'x'}}))
    })


    // cleanup db
    //
    await pg`
    do $$ begin
    drop schema if exists test_util_jtd cascade;
    end; $$;
    `

    await pg.end()
})

