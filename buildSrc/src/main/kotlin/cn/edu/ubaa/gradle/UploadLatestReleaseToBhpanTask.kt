package cn.edu.ubaa.gradle

import java.io.RandomAccessFile
import java.net.CookieManager
import java.net.CookiePolicy
import java.net.HttpCookie
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.time.Duration
import java.util.Properties
import kotlin.io.path.exists
import kotlin.io.path.inputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.TaskAction

private const val SSO_URL = "https://sso.buaa.edu.cn"
private const val BHPAN_URL = "https://bhpan.buaa.edu.cn"
private const val RELEASE_PREFIX = "UBAA-"
private val JSON = Json { ignoreUnknownKeys = true }

data class BhpanCredentials(
    val username: String,
    val password: String,
    val docId: String,
) {
  companion object {
    fun fromProperties(properties: Properties): BhpanCredentials {
      fun read(vararg keys: String): String? =
          keys
              .asSequence()
              .mapNotNull { key -> properties.getProperty(key)?.trim()?.takeIf(String::isNotEmpty) }
              .firstOrNull()

      val username =
          read("BHPAN_USER", "BHPAN_SSO_USERNAME", "testuser")
              ?: throw IllegalArgumentException(
                  "Missing BHPAN username in local.properties (expected BHPAN_USER)",
              )
      val password =
          read("BHPAN_PASSWORD", "BHPAN_SSO_PASSWORD", "testpasswd")
              ?: throw IllegalArgumentException(
                  "Missing BHPAN password in local.properties (expected BHPAN_PASSWORD)",
              )
      val docId =
          read("BHPAN_DOC_ID", "BHPAN_SHARED_FOLDER_DOCID")
              ?: throw IllegalArgumentException(
                  "Missing BHPAN doc id in local.properties (expected BHPAN_DOC_ID)",
              )
      return BhpanCredentials(username = username, password = password, docId = docId)
    }
  }
}

data class ReleaseAsset(
    val name: String,
    val downloadUrl: String,
    val size: Long,
)

data class GithubLatestRelease(
    val tagName: String,
    val assets: List<ReleaseAsset>,
)

data class BhpanRemoteFile(
    val docId: String,
    val name: String,
)

data class MultipartCompletionParts(
    val xml: String,
    val json: String,
)

object UploadPlan {
  const val smallUploadMaxSize: Long = 100L * 1024L * 1024L
  const val partSize: Long = 20L * 1024L * 1024L

  fun requiresMultipart(fileSize: Long): Boolean = fileSize > smallUploadMaxSize
}

object GithubLatestReleaseParser {
  fun parse(responseBody: String): GithubLatestRelease {
    val root = JSON.parseToJsonElement(responseBody).jsonObject
    val tagName = root.requireString("tag_name")
    val assets =
        root["assets"]
            ?.jsonArray
            ?.mapNotNull { assetElement ->
              val asset = assetElement.jsonObject
              val name = asset.requireString("name")
              if (!name.startsWith(RELEASE_PREFIX)) {
                return@mapNotNull null
              }
              ReleaseAsset(
                  name = name,
                  downloadUrl = asset.requireString("browser_download_url"),
                  size = asset.requireLong("size"),
              )
            }
            .orEmpty()
    return GithubLatestRelease(tagName = tagName, assets = assets)
  }
}

object BhpanDirectoryParser {
  fun releaseDocIds(listingJson: String): List<String> = releaseFiles(listingJson).map { it.docId }

  fun releaseFiles(listingJson: String): List<BhpanRemoteFile> {
    val root = JSON.parseToJsonElement(listingJson).jsonObject
    return root["files"]
        ?.jsonArray
        ?.mapNotNull { fileElement ->
          val file = fileElement.jsonObject
          val name = file["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
          val docId = file["docid"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
          if (!name.startsWith(RELEASE_PREFIX)) {
            return@mapNotNull null
          }
          BhpanRemoteFile(docId = docId, name = name)
        }
        .orEmpty()
  }

  fun containsFile(listingJson: String, fileName: String): Boolean =
      releaseFiles(listingJson).any { it.name == fileName }
}

object BhpanMultipartCompletionParser {
  private val xmlRegex = Regex("<[\\s\\S]*?(?=\\r?\\n--)")
  private val jsonRegex = Regex("\\{[\\s\\S]*?(?=\\r?\\n--)")

  fun parse(responseBody: String): MultipartCompletionParts {
    val xml =
        xmlRegex.find(responseBody)?.value
            ?: throw GradleException("Failed to parse multipart completion XML payload")
    val json =
        jsonRegex.find(responseBody)?.value
            ?: throw GradleException("Failed to parse multipart completion JSON payload")
    return MultipartCompletionParts(xml = xml, json = json)
  }
}

abstract class UploadLatestReleaseToBhpanTask : DefaultTask() {
  @get:Input abstract val repository: Property<String>

  @get:InputFile abstract val localPropertiesFile: RegularFileProperty

  init {
    group = "release"
    description =
        "Downloads the latest GitHub release assets and uploads them to BUAA Cloud Disk using local.properties credentials."
    outputs.upToDateWhen { false }
  }

  @TaskAction
  fun uploadLatestRelease() {
    val propertiesPath = localPropertiesFile.get().asFile.toPath()
    val credentials = BhpanCredentials.fromProperties(loadProperties(propertiesPath))
    val http = ManagedHttpSession()
    val githubClient = GithubReleaseClient(http)
    val release = githubClient.fetchLatestRelease(repository.get())
    if (release.assets.isEmpty()) {
      throw GradleException(
          "Latest release ${release.tagName} does not contain any $RELEASE_PREFIX assets"
      )
    }

    val artifactDirectory = temporaryDir.toPath().resolve("release-assets")
    recreateDirectory(artifactDirectory)
    logger.lifecycle("=== BUAA Cloud Disk Upload ===")
    logger.lifecycle("Latest release: ${release.tagName}")
    logger.lifecycle("Artifact directory: $artifactDirectory")
    logger.lifecycle("Found ${release.assets.size} release asset(s) to download.")
    release.assets.forEach { asset ->
      val target = artifactDirectory.resolve(asset.name)
      logger.lifecycle("Downloading: ${asset.name}")
      githubClient.downloadAsset(asset, target)
    }

    val bhpanClient = BhpanClient(http = http, credentials = credentials, logger = logger)
    bhpanClient.ssoLogin()
    bhpanClient.authenticate()
    bhpanClient.deleteOldFiles()
    bhpanClient.uploadAll(artifactDirectory)
    logger.lifecycle("=== Upload complete ===")
  }
}

private class GithubReleaseClient(private val http: ManagedHttpSession) {
  fun fetchLatestRelease(repository: String): GithubLatestRelease {
    val request =
        requestBuilder("https://api.github.com/repos/$repository/releases/latest")
            .GET()
            .header("Accept", "application/vnd.github+json")
            .build()
    val response = http.sendText(request)
    ensureSuccess(response, "Fetch latest GitHub release")
    return GithubLatestReleaseParser.parse(response.body())
  }

  fun downloadAsset(asset: ReleaseAsset, target: Path) {
    val request = requestBuilder(asset.downloadUrl).GET().build()
    val response = http.downloadToFile(request, target)
    ensureSuccess(response, "Download release asset ${asset.name}")
  }
}

private class BhpanClient(
    private val http: ManagedHttpSession,
    private val credentials: BhpanCredentials,
    private val logger: org.gradle.api.logging.Logger,
) {
  fun ssoLogin() {
    logger.lifecycle("Logging in to SSO...")
    val loginPageResponse = http.sendText(requestBuilder("$SSO_URL/login").GET().build())
    ensureSuccess(loginPageResponse, "Fetch SSO login page")
    val execution = extractExecutionToken(loginPageResponse.body())

    submitSsoLogin(execution = execution, eventId = "submit")
    if (!http.hasCookie("TGC")) {
      val continuePageResponse = http.sendText(requestBuilder("$SSO_URL/login").GET().build())
      ensureSuccess(continuePageResponse, "Fetch SSO continue page")
      val continueExecution = extractExecutionTokenOrNull(continuePageResponse.body())
      if (continueExecution != null) {
        submitSsoLogin(execution = continueExecution, eventId = "ignoreAndContinue")
      }
    }
    logger.lifecycle("SSO login completed.")
  }

  fun authenticate() {
    logger.lifecycle("Authenticating with BUAA Cloud Disk...")
    val authResponse =
        http.sendText(
            requestBuilder("$BHPAN_URL/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal")
                .GET()
                .build(),
            followRedirects = false,
        )
    val authUrl = redirectLocation(authResponse, "OAuth2 login redirect")

    val signInResponse =
        http.sendText(requestBuilder(authUrl).GET().build(), followRedirects = false)
    val signInUrl = redirectLocation(signInResponse, "OAuth2 sign-in redirect")
    val loginChallenge =
        Regex("""[?&]login_challenge=([^&]+)""").find(signInUrl)?.groupValues?.get(1)
            ?: throw GradleException("No login_challenge in redirect chain")
    http.addCookie(URI.create(BHPAN_URL), "login_challenge", loginChallenge, secure = true)

    val callbackResponse =
        http.sendDiscarding(
            requestBuilder(
                    "$SSO_URL/login?service=https%3A%2F%2Fbhpan.buaa.edu.cn%2Foauth2%2Fsignin"
                )
                .GET()
                .build(),
        )
    val callbackUrl = callbackResponse.uri().toString()
    if (!callbackUrl.contains("/login/callback")) {
      throw GradleException("OAuth2 redirect did not land on callback. Got: $callbackUrl")
    }
    if (http.cookieValue("client.oauth2_token").isNullOrBlank()) {
      throw GradleException("Failed to obtain OAuth2 token from bhpan")
    }
    logger.lifecycle("Cloud Disk authentication completed.")
  }

  fun deleteOldFiles() {
    logger.lifecycle("Listing files in shared folder...")
    val listing = listDirectory(credentials.docId)
    val oldFiles = BhpanDirectoryParser.releaseFiles(listing)
    logger.lifecycle("Found ${oldFiles.size} old UBAA files to delete.")
    oldFiles.forEach { file ->
      logger.lifecycle("  Deleting: ${file.name}")
      runCatching {
            apiJson(
                method = "POST",
                endpoint = "/api/efast/v1/file/delete",
                body = buildJsonObject { put("docid", JsonPrimitive(file.docId)) }.toString(),
            )
          }
          .onFailure { error ->
            logger.warn(
                "  Warning: failed to delete ${file.name}, continuing... (${error.message})"
            )
          }
    }
    logger.lifecycle("Old file cleanup completed.")
  }

  fun uploadAll(artifactDirectory: Path) {
    val files =
        Files.list(artifactDirectory).use { paths ->
          paths
              .filter {
                Files.isRegularFile(it) && it.fileName.toString().startsWith(RELEASE_PREFIX)
              }
              .sorted()
              .toList()
        }
    if (files.isEmpty()) {
      throw GradleException("No $RELEASE_PREFIX artifacts found in $artifactDirectory")
    }
    files.forEach { uploadFile(it) }
    logger.lifecycle("Uploaded ${files.size} files to BUAA Cloud Disk.")
  }

  private fun uploadFile(file: Path) {
    val fileName = file.fileName.toString()
    val fileSize = Files.size(file)
    logger.lifecycle("  Uploading: $fileName ($fileSize bytes)")
    if (UploadPlan.requiresMultipart(fileSize)) {
      uploadBigFile(file, fileName, fileSize)
    } else {
      uploadSmallFile(file, fileName, fileSize)
    }
  }

  private fun uploadSmallFile(file: Path, fileName: String, fileSize: Long) {
    val beginPayload =
        buildJsonObject {
              put("client_mtime", JsonPrimitive(System.currentTimeMillis()))
              put("docid", JsonPrimitive(credentials.docId))
              put("length", JsonPrimitive(fileSize))
              put("name", JsonPrimitive(fileName))
              put("ondup", JsonPrimitive(1))
            }
            .toString()
    val beginResponse =
        JSON.parseToJsonElement(
                apiJson(
                    method = "POST",
                    endpoint = "/api/efast/v1/file/osbeginupload",
                    body = beginPayload,
                ),
            )
            .jsonObject
    val putUrl = beginResponse.requireArray("authrequest").url()
    val docId = beginResponse.requireString("docid")
    val rev = beginResponse.requireString("rev")
    val headers = beginResponse.requireArray("authrequest").headerPairs()

    var lastFailure: String? = null
    repeat(3) { attempt ->
      val uploadResponse =
          http.sendText(
              requestBuilder(putUrl)
                  .timeout(Duration.ofMinutes(10))
                  .PUT(HttpRequest.BodyPublishers.ofFile(file))
                  .applyHeaders(headers)
                  .build(),
          )
      if (uploadResponse.statusCode() in 200..299) {
        completeUpload(fileName = fileName, docId = docId, rev = rev)
        return
      }
      lastFailure = "HTTP ${uploadResponse.statusCode()} ${uploadResponse.body().take(200)}"
      if (attempt < 2) {
        logger.lifecycle("  Retry ${attempt + 1}/3 for $fileName...")
        Thread.sleep(5_000)
      }
    }
    throw GradleException(
        "Failed to upload $fileName after 3 attempts${lastFailure?.let { ": $it" } ?: ""}"
    )
  }

  private fun uploadBigFile(file: Path, fileName: String, fileSize: Long) {
    logger.lifecycle("  Using multipart upload for large artifact: $fileName")
    val initPayload =
        buildJsonObject {
              put("docid", JsonPrimitive(credentials.docId))
              put("length", JsonPrimitive(fileSize))
              put("name", JsonPrimitive(fileName))
              put("ondup", JsonPrimitive(1))
            }
            .toString()
    val initResponse =
        JSON.parseToJsonElement(
                apiJson(
                    method = "POST",
                    endpoint = "/api/efast/v1/file/osinitmultiupload",
                    body = initPayload,
                ),
            )
            .jsonObject
    val docId = initResponse.requireString("docid")
    val rev = initResponse.requireString("rev")
    val uploadId = initResponse.requireString("uploadid")

    val partCount = ((fileSize + UploadPlan.partSize - 1) / UploadPlan.partSize).toInt()
    val partsPayload =
        buildJsonObject {
              put("docid", JsonPrimitive(docId))
              put("rev", JsonPrimitive(rev))
              put("uploadid", JsonPrimitive(uploadId))
              put("parts", JsonPrimitive("1-$partCount"))
            }
            .toString()
    val partResponse =
        JSON.parseToJsonElement(
                apiJson(
                    method = "POST",
                    endpoint = "/api/efast/v1/file/osuploadpart",
                    body = partsPayload,
                ),
            )
            .jsonObject

    val authRequests = partResponse.requireObject("authrequests")
    val partInfo = buildJsonObject {
      authRequests.keys.sortedBy(String::toInt).forEach { partKey ->
        val authRequest = authRequests.requireArray(partKey)
        val partNumber = partKey.toInt()
        val partBytes = readPart(file, partNumber = partNumber, partSize = UploadPlan.partSize)
        val uploadResponse =
            http.sendDiscarding(
                requestBuilder(authRequest.url())
                    .timeout(Duration.ofMinutes(10))
                    .header("Content-Length", partBytes.size.toString())
                    .applyHeaders(authRequest.headerPairs())
                    .PUT(HttpRequest.BodyPublishers.ofByteArray(partBytes))
                    .build(),
            )
        ensureSuccess(uploadResponse, "Upload multipart part $partNumber for $fileName")
        val etag =
            uploadResponse.headers().firstValue("ETag").orElseGet {
              uploadResponse.headers().firstValue("etag").orElse("")
            }
        if (etag.isBlank()) {
          throw GradleException("Missing ETag for $fileName part $partNumber")
        }
        put(
            partKey,
            buildJsonArray {
              add(JsonPrimitive(etag.trim().trim('"')))
              add(JsonPrimitive(partBytes.size))
            },
        )
      }
    }

    val completionPayload =
        buildJsonObject {
              put("docid", JsonPrimitive(docId))
              put("rev", JsonPrimitive(rev))
              put("uploadid", JsonPrimitive(uploadId))
              put("partinfo", partInfo)
            }
            .toString()
    val completionResponseBody =
        apiJson(
            method = "POST",
            endpoint = "/api/efast/v1/file/oscompleteupload",
            body = completionPayload,
        )
    val completionParts = BhpanMultipartCompletionParser.parse(completionResponseBody)
    val completionJson = JSON.parseToJsonElement(completionParts.json).jsonObject
    val completionRequest = completionJson.requireArray("authrequest")
    val completionResponse =
        http.sendDiscarding(
            requestBuilder(completionRequest.url())
                .timeout(Duration.ofMinutes(10))
                .applyHeaders(completionRequest.headerPairs())
                .POST(HttpRequest.BodyPublishers.ofString(completionParts.xml))
                .build(),
        )
    ensureSuccess(completionResponse, "Complete multipart upload for $fileName")
    completeUpload(fileName = fileName, docId = docId, rev = rev)
  }

  private fun completeUpload(fileName: String, docId: String, rev: String) {
    val endResponse =
        JSON.parseToJsonElement(
                apiJson(
                    method = "POST",
                    endpoint = "/api/efast/v1/file/osendupload",
                    body =
                        buildJsonObject {
                              put("docid", JsonPrimitive(docId))
                              put("rev", JsonPrimitive(rev))
                            }
                            .toString(),
                ),
            )
            .jsonObject
    if ("error" in endResponse) {
      throw GradleException("osendupload failed for $fileName: $endResponse")
    }
    verifyUploadedFile(fileName)
    logger.lifecycle("  Uploaded: $fileName")
  }

  private fun verifyUploadedFile(fileName: String) {
    repeat(5) {
      val listing = listDirectory(credentials.docId)
      if (BhpanDirectoryParser.containsFile(listing, fileName)) {
        return
      }
      Thread.sleep(2_000)
    }
    throw GradleException("Uploaded file is not visible in the target directory: $fileName")
  }

  private fun listDirectory(docId: String): String =
      apiJson(
          method = "POST",
          endpoint = "/api/efast/v1/dir/list",
          body =
              buildJsonObject {
                    put("by", JsonPrimitive("name"))
                    put("docid", JsonPrimitive(docId))
                    put("sort", JsonPrimitive("asc"))
                  }
                  .toString(),
      )

  private fun apiJson(method: String, endpoint: String, body: String): String {
    val token =
        http.cookieValue("client.oauth2_token")
            ?: throw GradleException("Missing client.oauth2_token cookie")
    val request =
        requestBuilder("$BHPAN_URL$endpoint")
            .timeout(Duration.ofSeconds(60))
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer $token")
            .method(method, HttpRequest.BodyPublishers.ofString(body))
            .build()
    val response = http.sendText(request)
    ensureSuccess(response, "BHPAN API call $endpoint")
    return response.body()
  }

  private fun submitSsoLogin(execution: String, eventId: String) {
    val request =
        requestBuilder("$SSO_URL/login")
            .timeout(Duration.ofSeconds(60))
            .header("Content-Type", "application/x-www-form-urlencoded")
            .POST(
                formBody(
                    linkedMapOf(
                        "username" to credentials.username,
                        "password" to credentials.password,
                        "submit" to "LOGIN",
                        "type" to "username_password",
                        "execution" to execution,
                        "_eventId" to eventId,
                    ),
                ),
            )
            .build()
    val response = http.sendDiscarding(request)
    ensureSuccess(response, "Submit SSO login ($eventId)")
  }

  private fun redirectLocation(response: HttpResponse<String>, context: String): String {
    if (response.statusCode() !in 300..399) {
      throw GradleException("$context failed: expected redirect, got HTTP ${response.statusCode()}")
    }
    return response.headers().firstValue("Location").orElseGet {
      response.headers().firstValue("location").orElseThrow {
        GradleException("$context failed: missing Location header")
      }
    }
  }
}

private class ManagedHttpSession {
  private val cookieManager = CookieManager(null, CookiePolicy.ACCEPT_ALL)
  private val redirectingClient =
      HttpClient.newBuilder()
          .cookieHandler(cookieManager)
          .connectTimeout(Duration.ofSeconds(30))
          .followRedirects(HttpClient.Redirect.NORMAL)
          .build()
  private val manualClient =
      HttpClient.newBuilder()
          .cookieHandler(cookieManager)
          .connectTimeout(Duration.ofSeconds(30))
          .followRedirects(HttpClient.Redirect.NEVER)
          .build()

  fun sendText(
      request: HttpRequest,
      followRedirects: Boolean = true,
  ): HttpResponse<String> =
      client(followRedirects)
          .send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))

  fun sendDiscarding(
      request: HttpRequest,
      followRedirects: Boolean = true,
  ): HttpResponse<Void> =
      client(followRedirects).send(request, HttpResponse.BodyHandlers.discarding())

  fun downloadToFile(
      request: HttpRequest,
      target: Path,
      followRedirects: Boolean = true,
  ): HttpResponse<Path> =
      client(followRedirects)
          .send(
              request,
              HttpResponse.BodyHandlers.ofFile(
                  target,
                  StandardOpenOption.CREATE,
                  StandardOpenOption.TRUNCATE_EXISTING,
                  StandardOpenOption.WRITE,
              ),
          )

  fun cookieValue(name: String): String? =
      cookieManager.cookieStore.cookies.firstOrNull { it.name == name }?.value

  fun hasCookie(name: String): Boolean = cookieValue(name) != null

  fun addCookie(uri: URI, name: String, value: String, secure: Boolean) {
    val cookie = HttpCookie(name, value)
    cookie.domain = uri.host
    cookie.path = "/"
    cookie.secure = secure
    cookieManager.cookieStore.add(uri, cookie)
  }

  private fun client(followRedirects: Boolean): HttpClient =
      if (followRedirects) redirectingClient else manualClient
}

private fun loadProperties(path: Path): Properties {
  if (!path.exists()) {
    throw GradleException("local.properties is required: $path")
  }
  return Properties().apply { path.inputStream().use(::load) }
}

private fun requestBuilder(url: String): HttpRequest.Builder =
    HttpRequest.newBuilder(URI.create(url))
        .timeout(Duration.ofSeconds(60))
        .header("User-Agent", "UBAA-Gradle-BHPAN-Uploader")

private fun extractExecutionToken(pageBody: String): String =
    extractExecutionTokenOrNull(pageBody)
        ?: throw GradleException("Failed to extract execution token from SSO login page")

private fun extractExecutionTokenOrNull(pageBody: String): String? =
    Regex("""name="execution"\s+value="([^"]+)"""").find(pageBody)?.groupValues?.get(1)

private fun ensureSuccess(response: HttpResponse<*>, context: String) {
  if (response.statusCode() !in 200..299) {
    throw GradleException("$context failed: HTTP ${response.statusCode()}")
  }
}

private fun formBody(parameters: Map<String, String>): HttpRequest.BodyPublisher =
    HttpRequest.BodyPublishers.ofString(
        parameters.entries.joinToString("&") { (key, value) ->
          "${key.urlEncode()}=${value.urlEncode()}"
        },
    )

private fun String.urlEncode(): String = URLEncoder.encode(this, StandardCharsets.UTF_8)

private fun HttpRequest.Builder.applyHeaders(headers: Map<String, String>): HttpRequest.Builder =
    apply {
      headers.forEach { (name, value) -> header(name, value) }
    }

private fun recreateDirectory(path: Path) {
  if (Files.exists(path)) {
    Files.walk(path).sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists)
  }
  Files.createDirectories(path)
}

private fun readPart(file: Path, partNumber: Int, partSize: Long): ByteArray {
  val offset = (partNumber - 1L) * partSize
  RandomAccessFile(file.toFile(), "r").use { randomAccessFile ->
    randomAccessFile.seek(offset)
    val remaining = randomAccessFile.length() - offset
    val currentSize = minOf(partSize, remaining).toInt()
    val buffer = ByteArray(currentSize)
    randomAccessFile.readFully(buffer)
    return buffer
  }
}

private fun JsonObject.requireString(name: String): String =
    this[name]?.jsonPrimitive?.contentOrNull
        ?: throw GradleException("Missing required JSON string field: $name")

private fun JsonObject.requireLong(name: String): Long =
    this[name]?.jsonPrimitive?.long
        ?: throw GradleException("Missing required JSON long field: $name")

private fun JsonObject.requireArray(name: String): JsonArray =
    this[name]?.jsonArray ?: throw GradleException("Missing required JSON array field: $name")

private fun JsonObject.requireObject(name: String): JsonObject =
    this[name]?.jsonObject ?: throw GradleException("Missing required JSON object field: $name")

private fun JsonArray.url(): String =
    getOrNull(1)?.jsonPrimitive?.contentOrNull ?: throw GradleException("Missing auth request URL")

private fun JsonArray.headerPairs(): Map<String, String> =
    drop(2).associate { headerElement ->
      val header = headerElement.jsonPrimitive.content
      val separatorIndex = header.indexOf(':')
      if (separatorIndex <= 0) {
        throw GradleException("Invalid auth request header: $header")
      }
      header.substring(0, separatorIndex).trim() to header.substring(separatorIndex + 1).trim()
    }
