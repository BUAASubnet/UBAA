package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

@Serializable data class ClassroomQueryResponse(val e: Int, val m: String, val d: ClassroomData)

@Serializable data class ClassroomData(val list: Map<String, List<ClassroomInfo>>)

@Serializable
data class ClassroomInfo(
        val id: String,
        val floorid: String,
        val name: String,
        val kxsds: String // "1,2,5,6,7,8,9,10,11,12,13,14"
)
