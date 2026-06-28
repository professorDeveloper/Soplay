package eu.kanade.tachiyomi.source.model

import android.net.Uri
import eu.kanade.tachiyomi.network.ProgressListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import rx.subjects.Subject
import java.io.Serializable

open class Page(
    val index: Int,
    val url: String = "",
    var imageUrl: String? = null,
    @Transient var uri: Uri? = null, // Deprecated but can't be deleted due to extensions
) : ProgressListener, Serializable {

    val number: Int
        get() = index + 1

    @Transient
    @Volatile
    var status: State = State.QUEUE

    @Transient
    private val _progressFlow = MutableStateFlow(0)

    @Transient
    val progressFlow = _progressFlow.asStateFlow()
    var progress: Int
        get() = _progressFlow.value
        set(value) {
            _progressFlow.value = value
        }

    @Transient
    @Volatile
    var totalBytesDownloaded: Long = 0L

    @Transient
    @Volatile
    var totalContentLength: Long = 0L

    @Transient
    @Volatile
    var bytesDownloaded: Long = 0L
        set(value) {
            totalBytesDownloaded += if (value < field) {
                value
            } else {
                value - field
            }
            field = value
        }

    @Transient
    var progressSubject: Subject<State, State>? = null

    override fun update(bytesRead: Long, contentLength: Long, done: Boolean) {
        bytesDownloaded = bytesRead
        if (contentLength > totalContentLength) {
            totalContentLength = contentLength
        }
        val newProgress = if (totalContentLength > 0) {
            (100 * totalBytesDownloaded / totalContentLength).toInt()
        } else {
            -1
        }
        if (progress != newProgress) progress = newProgress
    }

    enum class State {
        QUEUE,
        LOAD_PAGE,
        DOWNLOAD_IMAGE,
        READY,
        ERROR,
    }
}
