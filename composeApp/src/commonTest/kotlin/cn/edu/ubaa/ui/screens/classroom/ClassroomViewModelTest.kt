package cn.edu.ubaa.ui.screens.classroom

import cn.edu.ubaa.model.dto.ClassroomInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ClassroomViewModelTest {

  private val classroomData =
    linkedMapOf(
      "\u4e09\u53f7\u697c" to
        listOf(
          ClassroomInfo(id = "1", floorid = "1J03", name = "3-101", kxsds = "1,2,3"),
          ClassroomInfo(id = "2", floorid = "1J03", name = "3-201", kxsds = "1,2,3"),
        ),
      "\u4e3b\u697c" to
        listOf(
          ClassroomInfo(id = "3", floorid = "1J07", name = "\u4e3b\u697c-201", kxsds = "4,5,6")
        ),
    )

  @Test
  fun shouldBuildOptionsFromReturnedBuildings() {
    val options = buildingOptionsFrom(classroomData)

    assertEquals(listOf(ALL_BUILDINGS, "\u4e09\u53f7\u697c", "\u4e3b\u697c"), options)
  }

  @Test
  fun shouldFilterBySelectedBuildingBeforeSearchQuery() {
    val filtered =
      filterClassroomData(classroomData, query = "", selectedBuilding = "\u4e3b\u697c")

    assertEquals(listOf("\u4e3b\u697c"), filtered.keys.toList())
    assertEquals(1, filtered["\u4e3b\u697c"]?.size)
  }

  @Test
  fun shouldKeepBuildingMatchWhenSearchingInsideSelectedBuilding() {
    val filtered =
      filterClassroomData(
        classroomData,
        query = "\u65b0\u4e3b\u697c",
        selectedBuilding = "\u4e3b\u697c",
      )

    assertTrue(filtered.isEmpty())
  }

  @Test
  fun shouldFilterByClassroomNameAcrossAllBuildings() {
    val filtered = filterClassroomData(classroomData, query = "201", selectedBuilding = ALL_BUILDINGS)

    assertEquals(listOf("\u4e09\u53f7\u697c", "\u4e3b\u697c"), filtered.keys.toList())
    assertEquals(listOf("3-201"), filtered["\u4e09\u53f7\u697c"]?.map { it.name })
    assertEquals(listOf("\u4e3b\u697c-201"), filtered["\u4e3b\u697c"]?.map { it.name })
  }

  @Test
  fun shouldUseFloorIdOrderingWhenEveryBuildingHasSingleStringFloorId() {
    val ordered =
      sortBuildings(
        linkedMapOf(
          "\u4e09\u53f7\u697c" to
            listOf(ClassroomInfo(id = "1", floorid = "2J03", name = "3-101", kxsds = "1,2")),
          "\u6559\u96f6\u697c" to
            listOf(ClassroomInfo(id = "2", floorid = "2J00", name = "J0-101", kxsds = "1,2")),
          "\u4e00\u53f7\u6559\u5b66\u697c" to
            listOf(ClassroomInfo(id = "3", floorid = "2J01", name = "J1-101", kxsds = "1,2")),
          "\u6c99\u6cb3\u6821\u533a\u4e8c\u53f7\u697c" to
            listOf(ClassroomInfo(id = "4", floorid = "2Z02", name = "SH2-101", kxsds = "1,2")),
        )
      )

    assertEquals(
      listOf("\u6559\u96f6\u697c", "\u4e00\u53f7\u6559\u5b66\u697c", "\u4e09\u53f7\u697c", "\u6c99\u6cb3\u6821\u533a\u4e8c\u53f7\u697c"),
      ordered,
    )
  }

  @Test
  fun shouldFallbackToNaturalOrderingWhenBuildingHasMultipleFloorIds() {
    val ordered =
      sortBuildings(
        linkedMapOf(
          "10\u53f7\u697c" to
            listOf(
              ClassroomInfo(id = "1", floorid = "10", name = "10-101", kxsds = "1,2"),
              ClassroomInfo(id = "2", floorid = "11", name = "10-102", kxsds = "1,2"),
            ),
          "2\u53f7\u697c" to
            listOf(ClassroomInfo(id = "3", floorid = "2", name = "2-101", kxsds = "1,2")),
          "\u6559\u96f6\u697c" to
            listOf(ClassroomInfo(id = "4", floorid = "0", name = "J0-101", kxsds = "1,2")),
        )
      )

    assertEquals(listOf("2\u53f7\u697c", "10\u53f7\u697c", "\u6559\u96f6\u697c"), ordered)
  }

  @Test
  fun shouldReportFloorIdValidationFailureForDuplicateBuildingFloorIds() {
    val analysis =
      analyzeBuildingFloorIds(
        linkedMapOf(
          "\u4e00\u53f7\u697c" to
            listOf(ClassroomInfo(id = "1", floorid = "2J01", name = "1-101", kxsds = "1,2")),
          "\u4e8c\u53f7\u697c" to
            listOf(ClassroomInfo(id = "2", floorid = "2J01", name = "2-101", kxsds = "1,2")),
        )
      )

    assertTrue(!analysis.canUseFloorIdOrdering)
  }
}
