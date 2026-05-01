package cn.edu.ubaa.judge

import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class JudgeSupportTest {
  @Test
  fun `parses brief answer rows with th number column`() {
    val html =
        """
        <html><body>
          作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
          作业满分： 100.00 ，共 2道 题
          <h5>简答题</h5>
          <table>
            <thead><tr><th>#</th><th>题目</th><th>分值</th><th>提交/评阅状态</th></tr></thead>
            <tbody>
              <tr><th>1.</th><td><a>设计说明</a></td><td>60.00</td><td>初次提交时间: 2026-04-17 12:24:26 最后一次修改时间: 2026-04-17 12:24:26</td></tr>
              <tr><th>2.</th><td><a>用例设计</a></td><td>40.00</td><td>未提交答案</td></tr>
            </tbody>
          </table>
        </body></html>
        """

    val detail =
        JudgeParsers.parseAssignmentDetail(
            html = html,
            courseId = "1",
            courseName = "软件工程",
            assignmentId = "101",
            title = "sample",
        )

    assertEquals("2026-04-20 19:00:00", detail.startTime)
    assertEquals("2026-05-03 23:00:00", detail.dueTime)
    assertEquals("100", detail.maxScore)
    assertNull(detail.myScore)
    assertEquals(2, detail.totalProblems)
    assertEquals(1, detail.submittedCount)
    assertEquals(JudgeSubmissionStatus.PARTIAL, detail.submissionStatus)
    assertEquals(listOf("设计说明", "用例设计"), detail.problems.map { it.name })
    assertEquals(
        listOf(JudgeSubmissionStatus.SUBMITTED, JudgeSubmissionStatus.UNSUBMITTED),
        detail.problems.map { it.status },
    )
  }

  @Test
  fun `parses programming rows without counting nested testcase tables`() {
    val html =
        """
        <html><body>
          作业满分： 20.00 ，共 2道 题
          <h5>编程题</h5>
          <table>
            <thead><tr><th>#</th><th>题目</th><th>分值</th><th>批阅信息</th></tr></thead>
            <tbody>
              <tr>
                <th>1.</th><td>程序一</td><td>10.00</td>
                <td>下载源文件 最后一次提交时间：2026-04-17 12:00:00 得分：8.00
                  <table><tr><th>name</th><th>verdict</th></tr><tr><td>TestCase1</td><td>Accept</td></tr></table>
                </td>
              </tr>
              <tr><th>2.</th><td>程序二</td><td>10.00</td><td>还未提交代码 详细</td></tr>
            </tbody>
          </table>
        </body></html>
        """

    val detail =
        JudgeParsers.parseAssignmentDetail(
            html = html,
            courseId = "1",
            courseName = "算法",
            assignmentId = "102",
            title = "sample",
        )

    assertEquals(2, detail.totalProblems)
    assertEquals(1, detail.submittedCount)
    assertEquals("8", detail.myScore)
    assertEquals(listOf("程序一", "程序二"), detail.problems.map { it.name })
  }

  @Test
  fun `parses file upload rows`() {
    val html =
        """
        <html><body>
          作业满分： 10.00 ，共 2道 题
          <h5>文件上传题</h5>
          <table>
            <thead><tr><th>#</th><th>题目</th><th>分值</th><th>提交状态</th></tr></thead>
            <tbody>
              <tr><th>1.</th><td>任务一</td><td>5.00</td><td>未提交文件</td></tr>
              <tr><th>2.</th><td>任务二</td><td>5.00</td><td>初次提交时间: 2026-04-09 15:03:32 最近一次提交时间: 2026-04-09 15:03:30 文件重命名为: 24182104.pdf 下载</td></tr>
            </tbody>
          </table>
        </body></html>
        """

    val detail =
        JudgeParsers.parseAssignmentDetail(
            html = html,
            courseId = "1",
            courseName = "工程实践",
            assignmentId = "103",
            title = "sample",
        )

    assertEquals(1, detail.submittedCount)
    assertEquals(
        listOf(JudgeSubmissionStatus.UNSUBMITTED, JudgeSubmissionStatus.SUBMITTED),
        detail.problems.map { it.status },
    )
  }

  @Test
  fun `parses choice and fill rows with two cells`() {
    val html =
        """
        <html><body>
          作业满分： 2.00 ，共 2道 题
          <h5>选择题</h5>
          <table>
            <tbody>
              <tr><th>1.</th><td>已提交 首次提交时间: 2026-04-14 19:38:38 最后一次提交时间: 2026-04-14 19:38:39 题干 得分：1.00</td></tr>
              <tr><th>2.</th><td>未作答 题干</td></tr>
            </tbody>
          </table>
        </body></html>
        """

    val detail =
        JudgeParsers.parseAssignmentDetail(
            html = html,
            courseId = "1",
            courseName = "概率统计",
            assignmentId = "104",
            title = "sample",
        )

    assertEquals(2, detail.totalProblems)
    assertEquals(1, detail.submittedCount)
    assertEquals("1", detail.myScore)
    assertEquals(listOf("第1题", "第2题"), detail.problems.map { it.name })
  }
}
