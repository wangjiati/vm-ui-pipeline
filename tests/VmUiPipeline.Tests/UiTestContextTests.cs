// Copyright (c) Files Community and VmUiPipeline contributors.
// SPDX-License-Identifier: MPL-2.0

using Microsoft.VisualStudio.TestTools.UnitTesting;
using VmUiPipeline.Testing;

namespace VmUiPipeline.Tests;

[TestClass]
public sealed class UiTestContextTests
{
    [TestMethod]
    public void Test_RecordsPassFailureAndSkip()
    {
        var context = new UiTestContext(null, null, null, null, _ => { });

        context.Test("pass", () => { });
        context.Test("fail", () => context.Assert(false, "boom"));
        context.Test("skip", () => throw new UiSkipException("not now"));
        context.Test("throws", () => throw new InvalidOperationException("kaboom"));

        Assert.AreEqual(4, context.Results.Count);
        Assert.AreEqual(TestStatus.Passed, context.Results[0].Status);
        Assert.AreEqual(TestStatus.Failed, context.Results[1].Status);
        Assert.AreEqual("boom", context.Results[1].Detail);
        Assert.AreEqual(TestStatus.Skipped, context.Results[2].Status);
        Assert.AreEqual(TestStatus.Failed, context.Results[3].Status);
        Assert.AreEqual("kaboom", context.Results[3].Detail);
    }

    [TestMethod]
    public void Test_FilterSkipsNonMatchingTests()
    {
        var context = new UiTestContext(null, null, null, "^smoke", _ => { });

        context.Test("other", () => throw new InvalidOperationException("should not run"));
        context.Test("smoke-one", () => { });
        context.Skip("smoke-two", "later");

        Assert.AreEqual(2, context.Results.Count);
        Assert.AreEqual("smoke-one", context.Results[0].Name);
        Assert.AreEqual(TestStatus.Passed, context.Results[0].Status);
        Assert.AreEqual("smoke-two", context.Results[1].Name);
        Assert.AreEqual(TestStatus.Skipped, context.Results[1].Status);
    }

    [TestMethod]
    public void WaitForCount_ReturnsWhenExpectedValueAppears()
    {
        var context = new UiTestContext(null, null, null, null, _ => { });
        var attempts = 0;

        var count = context.WaitForCount(
            () => ++attempts >= 3 ? 2 : 0,
            2,
            TimeSpan.FromSeconds(2),
            "rows");

        Assert.AreEqual(2, count);
        Assert.IsTrue(attempts >= 3);
    }

    [TestMethod]
    public void WaitForCount_ThrowsWithLastValue()
    {
        var context = new UiTestContext(null, null, null, null, _ => { });

        var exception = Assert.ThrowsExactly<UiAssertionException>(
            () => context.WaitForCount(() => 1, 2, TimeSpan.FromMilliseconds(150), "rows"));

        StringAssert.Contains(exception.Message, "rows=2");
        StringAssert.Contains(exception.Message, "last value was 1");
    }

    [TestMethod]
    public void Parameters_AreCaseInsensitive()
    {
        var context = new UiTestContext(
            null,
            null,
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["Folder"] = "C:\\fixture" },
            null,
            _ => { });

        Assert.AreEqual("C:\\fixture", context.Parameters["folder"]);
    }
}
