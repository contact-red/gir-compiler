// Tests for gir-package helpers.

use "pony_check"
use "pony_test"


actor Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestPonyIdentParamPassThrough)
    test(_TestPonyIdentParamHyphens)
    test(_TestPonyIdentParamTrailingUnderscore)
    test(_TestPonyIdentParamReservedSuffix)
    test(_TestPonyIdentMethodReservedPrefix)
    test(_TestPonyIdentParamEmpty)
    test(_TestPonyIdentMethodEmpty)
    test(_TestPonyIdentIsReserved)
    test(Property1UnitTest[String val](_PropPonyIdentParamIsTotal))
    test(Property1UnitTest[String val](_PropPonyIdentMethodIsTotal))


class iso _TestPonyIdentParamPassThrough is UnitTest
  fun name(): String => "PonyIdent/safe_param/non-reserved snake_case unchanged"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("set_title", PonyIdent.safe_param("set_title"))
    h.assert_eq[String]("show", PonyIdent.safe_param("show"))
    h.assert_eq[String]("connect_activate",
      PonyIdent.safe_param("connect_activate"))


class iso _TestPonyIdentParamHyphens is UnitTest
  fun name(): String => "PonyIdent/safe_param/hyphens become underscores"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("close_request",
      PonyIdent.safe_param("close-request"))


class iso _TestPonyIdentParamTrailingUnderscore is UnitTest
  fun name(): String => "PonyIdent/safe_param/trailing underscores stripped"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("foo", PonyIdent.safe_param("foo_"))
    h.assert_eq[String]("foo", PonyIdent.safe_param("foo___"))


class iso _TestPonyIdentParamReservedSuffix is UnitTest
  fun name(): String => "PonyIdent/safe_param/reserved -> name'"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("match'", PonyIdent.safe_param("match"))
    h.assert_eq[String]("ref'",   PonyIdent.safe_param("ref"))
    h.assert_eq[String]("error'", PonyIdent.safe_param("error"))


class iso _TestPonyIdentMethodReservedPrefix is UnitTest
  fun name(): String => "PonyIdent/safe_method/reserved -> gname"
  fun apply(h: TestHelper) =>
    // Pony method names disallow primes; the method-name munge has
    // to use a different scheme. We prepend `g` (matching the
    // GObject naming convention).
    h.assert_eq[String]("gmatch", PonyIdent.safe_method("match"))
    h.assert_eq[String]("gref",   PonyIdent.safe_method("ref"))
    h.assert_eq[String]("gerror", PonyIdent.safe_method("error"))
    // Non-reserved passes through unchanged.
    h.assert_eq[String]("show",   PonyIdent.safe_method("show"))


class iso _TestPonyIdentParamEmpty is UnitTest
  fun name(): String => "PonyIdent/safe_param/empty -> arg"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("arg", PonyIdent.safe_param(""))
    h.assert_eq[String]("arg", PonyIdent.safe_param("___"))


class iso _TestPonyIdentMethodEmpty is UnitTest
  fun name(): String => "PonyIdent/safe_method/empty -> method"
  fun apply(h: TestHelper) =>
    h.assert_eq[String]("method", PonyIdent.safe_method(""))
    h.assert_eq[String]("method", PonyIdent.safe_method("___"))


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


class iso _PropPonyIdentParamIsTotal is Property1[String val]
  fun name(): String => "PonyIdent/safe_param/property: total"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 40)

  fun property(arg1: String val, ph: PropertyHelper) =>
    let result = PonyIdent.safe_param(arg1)
    ph.assert_true(result.size() > 0,
      "expected non-empty result for input: " + arg1)


class iso _PropPonyIdentMethodIsTotal is Property1[String val]
  fun name(): String => "PonyIdent/safe_method/property: total"

  fun gen(): Generator[String val] =>
    Generators.ascii_printable(0, 40)

  fun property(arg1: String val, ph: PropertyHelper) =>
    let result = PonyIdent.safe_method(arg1)
    ph.assert_true(result.size() > 0,
      "expected non-empty result for input: " + arg1)
