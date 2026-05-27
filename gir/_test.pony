// Tests for gir-package helpers.

use "pony_check"
use "pony_test"


actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestPonyIdentPassThrough)
    test(_TestPonyIdentHyphens)
    test(_TestPonyIdentTrailingUnderscore)
    test(_TestPonyIdentReservedMatch)
    test(_TestPonyIdentReservedRef)
    test(_TestPonyIdentReservedError)
    test(_TestPonyIdentEmpty)
    test(_TestPonyIdentIsReserved)
    test(Property1UnitTest[String val](_PropPonyIdentIsTotal))


class iso _TestPonyIdentPassThrough is UnitTest
  fun name(): String => "PonyIdent/non-reserved snake_case unchanged"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("set_title", PonyIdent.safe("set_title"))
    h.assert_eq[String]("show", PonyIdent.safe("show"))
    h.assert_eq[String]("connect_activate", PonyIdent.safe("connect_activate"))


class iso _TestPonyIdentHyphens is UnitTest
  fun name(): String => "PonyIdent/hyphens become underscores"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("close_request", PonyIdent.safe("close-request"))


class iso _TestPonyIdentTrailingUnderscore is UnitTest
  fun name(): String => "PonyIdent/trailing underscores stripped"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("foo", PonyIdent.safe("foo_"))
    h.assert_eq[String]("foo", PonyIdent.safe("foo___"))


class iso _TestPonyIdentReservedMatch is UnitTest
  fun name(): String => "PonyIdent/match -> match'"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("match'", PonyIdent.safe("match"))


class iso _TestPonyIdentReservedRef is UnitTest
  fun name(): String => "PonyIdent/ref -> ref'"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("ref'", PonyIdent.safe("ref"))


class iso _TestPonyIdentReservedError is UnitTest
  fun name(): String => "PonyIdent/error -> error'"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("error'", PonyIdent.safe("error"))


class iso _TestPonyIdentEmpty is UnitTest
  fun name(): String => "PonyIdent/empty -> arg"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("arg", PonyIdent.safe(""))
    // Also: a string of only underscores collapses to empty after
    // trim, which then becomes "arg".
    h.assert_eq[String]("arg", PonyIdent.safe("___"))


class iso _TestPonyIdentIsReserved is UnitTest
  fun name(): String => "PonyIdent/is_reserved covers the catalog"
  fun apply(h: TestHelper) =>
    h.assert_true(PonyIdent.is_reserved("match"))
    h.assert_true(PonyIdent.is_reserved("ref"))
    h.assert_true(PonyIdent.is_reserved("error"))
    h.assert_true(PonyIdent.is_reserved("new"))
    h.assert_true(PonyIdent.is_reserved("box"))
    h.assert_true(PonyIdent.is_reserved("iso"))
    h.assert_false(PonyIdent.is_reserved("set_title"))
    h.assert_false(PonyIdent.is_reserved("show"))


class iso _PropPonyIdentIsTotal is Property1[String val]
  fun name(): String => "PonyIdent/property: total — no input panics"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 40)

  fun property(arg1: String val, ph: PropertyHelper) =>
    // The contract: PonyIdent.safe always returns a non-empty string
    // for any input. We don't check the result is a valid Pony
    // identifier (that's harder to assert in a property), but
    // emptiness and trivial absence-of-panic is checked.
    let result = PonyIdent.safe(arg1)
    ph.assert_true(result.size() > 0,
      "expected non-empty result for input: " + arg1)
