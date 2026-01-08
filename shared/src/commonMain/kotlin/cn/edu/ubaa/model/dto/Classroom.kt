package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/** 教室查询 API 顶层响应体。 */
@Serializable data class ClassroomQueryResponse(val e: Int, val m: String, val d: ClassroomData)

/** 教室查询数据包裹类。 */
@Serializable data class ClassroomData(val list: Map<String, List<ClassroomInfo>>)

/**
 * 教室详细信息。
 *
 * @property id 教室 ID。
 * @property floorid 楼栋/楼层 ID。
 * @property name 教室名称（如“J1-101”）。
 * @property kxsds 空闲节次描述（逗号分隔的节次序号字符串）。
 */
@Serializable
data class ClassroomInfo(
  val id: String,
  val floorid: String,
  val name: String,
  val kxsds: String, // "1,2,5,6,7,8,9,10,11,12,13,14"
)
