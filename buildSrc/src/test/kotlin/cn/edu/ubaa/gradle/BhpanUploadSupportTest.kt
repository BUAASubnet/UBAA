package cn.edu.ubaa.gradle

import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class BhpanUploadSupportTest {
  @Test
  fun `loads bhpan credentials from explicit local properties keys`() {
    val properties =
        Properties().apply {
          setProperty("BHPAN_USER", "user1")
          setProperty("BHPAN_PASSWORD", "pass1")
          setProperty("BHPAN_DOC_ID", "gns://doc/1")
        }

    val credentials = BhpanCredentials.fromProperties(properties)

    assertEquals("user1", credentials.username)
    assertEquals("pass1", credentials.password)
    assertEquals("gns://doc/1", credentials.docId)
  }

  @Test
  fun `loads bhpan credentials from legacy fallback keys`() {
    val properties =
        Properties().apply {
          setProperty("BHPAN_SSO_USERNAME", "legacy-user")
          setProperty("BHPAN_SSO_PASSWORD", "legacy-pass")
          setProperty("BHPAN_SHARED_FOLDER_DOCID", "gns://legacy/doc")
        }

    val credentials = BhpanCredentials.fromProperties(properties)

    assertEquals("legacy-user", credentials.username)
    assertEquals("legacy-pass", credentials.password)
    assertEquals("gns://legacy/doc", credentials.docId)
  }

  @Test
  fun `fails when bhpan credentials are incomplete`() {
    val properties = Properties().apply { setProperty("BHPAN_USER", "only-user") }

    assertFailsWith<IllegalArgumentException> { BhpanCredentials.fromProperties(properties) }
  }

  @Test
  fun `parses latest release assets and keeps only ub aa artifacts`() {
    val releaseJson =
        """
        {
          "tag_name": "v1.7.2",
          "assets": [
            {
              "name": "UBAA-Android-v1.7.2.apk",
              "browser_download_url": "https://example.com/android.apk",
              "size": 123
            },
            {
              "name": "Source code.zip",
              "browser_download_url": "https://example.com/source.zip",
              "size": 456
            },
            {
              "name": "UBAA-Windows-v1.7.2.exe",
              "browser_download_url": "https://example.com/windows.exe",
              "size": 789
            }
          ]
        }
        """
            .trimIndent()

    val release = GithubLatestReleaseParser.parse(releaseJson)

    assertEquals("v1.7.2", release.tagName)
    assertEquals(
        listOf("UBAA-Android-v1.7.2.apk", "UBAA-Windows-v1.7.2.exe"),
        release.assets.map { it.name },
    )
    assertEquals(
        listOf("https://example.com/android.apk", "https://example.com/windows.exe"),
        release.assets.map { it.downloadUrl },
    )
  }

  @Test
  fun `finds only ub aa docids for cleanup`() {
    val listingJson =
        """
        {
          "files": [
            { "docid": "doc-a", "name": "UBAA-Android-v1.7.2.apk" },
            { "docid": "doc-b", "name": "notes.txt" },
            { "docid": "doc-c", "name": "UBAA-Windows-v1.7.2.exe" }
          ]
        }
        """
            .trimIndent()

    val docIds = BhpanDirectoryParser.releaseDocIds(listingJson)

    assertEquals(listOf("doc-a", "doc-c"), docIds)
  }

  @Test
  fun `uses multipart upload only for files larger than small upload threshold`() {
    assertEquals(false, UploadPlan.requiresMultipart(100L * 1024 * 1024))
    assertEquals(true, UploadPlan.requiresMultipart(100L * 1024 * 1024 + 1))
  }

  @Test
  fun `parses multipart completion response into xml and json`() {
    val response =
        """
        --boundary
        Content-Type: application/xml

        <CompleteMultipartUpload><Part>1</Part></CompleteMultipartUpload>
        --boundary
        Content-Type: application/json

        {"authrequest":["POST","https://upload.example.com/complete","x-test: 1"]}
        --boundary--
        """
            .trimIndent()

    val parts = BhpanMultipartCompletionParser.parse(response)

    assertEquals(
        "<CompleteMultipartUpload><Part>1</Part></CompleteMultipartUpload>",
        parts.xml.trim(),
    )
    assertEquals(
        """{"authrequest":["POST","https://upload.example.com/complete","x-test: 1"]}""",
        parts.json.trim(),
    )
  }
}
