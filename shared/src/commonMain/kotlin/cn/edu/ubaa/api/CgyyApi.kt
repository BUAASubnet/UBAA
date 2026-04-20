package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CgyyDayInfoResponse
import cn.edu.ubaa.model.dto.CgyyLockCodeResponse
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.CgyyOrdersPageResponse
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyReservationSubmitResponse
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

interface CgyyApiBackend {
  suspend fun getVenueSites(): Result<List<CgyyVenueSiteDto>>

  suspend fun getPurposeTypes(): Result<List<CgyyPurposeTypeDto>>

  suspend fun getDayInfo(venueSiteId: Int, date: String): Result<CgyyDayInfoResponse>

  suspend fun submitReservation(
      request: CgyyReservationSubmitRequest
  ): Result<CgyyReservationSubmitResponse>

  suspend fun getMyOrders(page: Int, size: Int): Result<CgyyOrdersPageResponse>

  suspend fun getOrderDetail(orderId: Int): Result<CgyyOrderDto>

  suspend fun cancelOrder(orderId: Int): Result<CgyyReservationSubmitResponse>

  suspend fun getLockCode(): Result<CgyyLockCodeResponse>
}

open class CgyyApi(
    private val backendProvider: () -> CgyyApiBackend = { ConnectionRuntime.apiFactory().cgyyApi() }
) {
  internal constructor(backend: CgyyApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayCgyyApiBackend(apiClient) })

  private fun currentBackend(): CgyyApiBackend = backendProvider()

  open suspend fun getVenueSites(): Result<List<CgyyVenueSiteDto>> {
    return currentBackend().getVenueSites()
  }

  open suspend fun getPurposeTypes(): Result<List<CgyyPurposeTypeDto>> {
    return currentBackend().getPurposeTypes()
  }

  open suspend fun getDayInfo(venueSiteId: Int, date: String): Result<CgyyDayInfoResponse> {
    return currentBackend().getDayInfo(venueSiteId, date)
  }

  open suspend fun submitReservation(
      request: CgyyReservationSubmitRequest
  ): Result<CgyyReservationSubmitResponse> {
    return currentBackend().submitReservation(request)
  }

  open suspend fun getMyOrders(page: Int = 0, size: Int = 20): Result<CgyyOrdersPageResponse> {
    return currentBackend().getMyOrders(page, size)
  }

  open suspend fun getOrderDetail(orderId: Int): Result<CgyyOrderDto> {
    return currentBackend().getOrderDetail(orderId)
  }

  open suspend fun cancelOrder(orderId: Int): Result<CgyyReservationSubmitResponse> {
    return currentBackend().cancelOrder(orderId)
  }

  open suspend fun getLockCode(): Result<CgyyLockCodeResponse> {
    return currentBackend().getLockCode()
  }
}

internal class RelayCgyyApiBackend(private val apiClient: ApiClient = ApiClientProvider.shared) :
    CgyyApiBackend {
  override suspend fun getVenueSites(): Result<List<CgyyVenueSiteDto>> {
    return safeApiCall { apiClient.getClient().get("api/v1/cgyy/sites") }
  }

  override suspend fun getPurposeTypes(): Result<List<CgyyPurposeTypeDto>> {
    return safeApiCall { apiClient.getClient().get("api/v1/cgyy/purpose-types") }
  }

  override suspend fun getDayInfo(venueSiteId: Int, date: String): Result<CgyyDayInfoResponse> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/cgyy/day-info") {
        parameter("venueSiteId", venueSiteId)
        parameter("date", date)
      }
    }
  }

  override suspend fun submitReservation(
      request: CgyyReservationSubmitRequest
  ): Result<CgyyReservationSubmitResponse> {
    return safeApiCall {
      apiClient.getClient().post("api/v1/cgyy/reservations") {
        contentType(ContentType.Application.Json)
        setBody(request)
      }
    }
  }

  override suspend fun getMyOrders(page: Int, size: Int): Result<CgyyOrdersPageResponse> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/cgyy/orders") {
        parameter("page", page)
        parameter("size", size)
      }
    }
  }

  override suspend fun getOrderDetail(orderId: Int): Result<CgyyOrderDto> {
    return safeApiCall { apiClient.getClient().get("api/v1/cgyy/orders/$orderId") }
  }

  override suspend fun cancelOrder(orderId: Int): Result<CgyyReservationSubmitResponse> {
    return safeApiCall { apiClient.getClient().post("api/v1/cgyy/orders/$orderId/cancel") }
  }

  override suspend fun getLockCode(): Result<CgyyLockCodeResponse> {
    return safeApiCall { apiClient.getClient().get("api/v1/cgyy/orders/lock-code") }
  }
}
