package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkClockinSubmitResponse
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkRecordsPageResponse
import io.ktor.client.request.forms.MultiPartFormDataContent
import io.ktor.client.request.forms.formData
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders

interface YgdkApiBackend {
  suspend fun getOverview(): Result<YgdkOverviewResponse>

  suspend fun getRecords(page: Int, size: Int): Result<YgdkRecordsPageResponse>

  suspend fun submitClockin(request: YgdkClockinSubmitRequest): Result<YgdkClockinSubmitResponse>
}

open class YgdkApi(
    private val backendProvider: () -> YgdkApiBackend = { ConnectionRuntime.apiFactory().ygdkApi() }
) {
  internal constructor(backend: YgdkApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayYgdkApiBackend(apiClient) })

  private fun currentBackend(): YgdkApiBackend = backendProvider()

  open suspend fun getOverview(): Result<YgdkOverviewResponse> {
    return currentBackend().getOverview()
  }

  open suspend fun getRecords(page: Int = 1, size: Int = 20): Result<YgdkRecordsPageResponse> {
    return currentBackend().getRecords(page, size)
  }

  open suspend fun submitClockin(
      request: YgdkClockinSubmitRequest
  ): Result<YgdkClockinSubmitResponse> {
    return currentBackend().submitClockin(request)
  }
}

internal class RelayYgdkApiBackend(private val apiClient: ApiClient = ApiClientProvider.shared) :
    YgdkApiBackend {
  override suspend fun getOverview(): Result<YgdkOverviewResponse> {
    return safeApiCall { apiClient.getClient().get("api/v1/ygdk/overview") }
  }

  override suspend fun getRecords(page: Int, size: Int): Result<YgdkRecordsPageResponse> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/ygdk/records") {
        parameter("page", page)
        parameter("size", size)
      }
    }
  }

  override suspend fun submitClockin(
      request: YgdkClockinSubmitRequest
  ): Result<YgdkClockinSubmitResponse> {
    return safeApiCall {
      apiClient.getClient().post("api/v1/ygdk/records") {
        setBody(
            MultiPartFormDataContent(
                formData {
                  request.itemId?.let { append("itemId", it.toString()) }
                  request.startTime?.takeIf { it.isNotBlank() }?.let { append("startTime", it) }
                  request.endTime?.takeIf { it.isNotBlank() }?.let { append("endTime", it) }
                  request.place?.takeIf { it.isNotBlank() }?.let { append("place", it) }
                  request.shareToSquare?.let { append("shareToSquare", it.toString()) }
                  request.photo?.let { photo ->
                    append(
                        "photo",
                        photo.bytes,
                        Headers.build {
                          append(
                              HttpHeaders.ContentDisposition,
                              "form-data; name=\"photo\"; filename=\"${photo.fileName}\"",
                          )
                          append(HttpHeaders.ContentType, photo.mimeType)
                        },
                    )
                  }
                }
            )
        )
      }
    }
  }
}
