package com.soplay.sozo.aniyomi

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class AniyomiHost(private val context: Context) {

    private data class SourceMeta(
        val id: String,
        val name: String,
        val lang: String,
        val baseUrl: String,
        val pkg: String,
        val className: String,
        val apkPath: String,
        val nsfw: Boolean,
        val repoName: String,
    )

    private val sources = LinkedHashMap<String, SourceMeta>()

    fun registerMeta(entry: JSONObject, repoName: String) {
        val id = entry.optString("id")
        if (id.isEmpty()) return
        sources[id] = SourceMeta(
            id = id,
            name = entry.optString("name"),
            lang = entry.optString("lang"),
            baseUrl = entry.optString("baseUrl"),
            pkg = entry.optString("pkg"),
            className = entry.optString("className"),
            apkPath = entry.optString("apkPath"),
            nsfw = entry.optBoolean("nsfw", false),
            repoName = repoName,
        )
    }

    fun removeSources(ids: List<String>) {
        ids.forEach { sources.remove(it) }
    }

    fun providersJson(): String {
        val arr = JSONArray()
        for (s in sources.values) {
            arr.put(JSONObject().apply {
                put("id", "an:${s.id}")
                put("name", s.name)
                put("lang", s.lang)
                put("baseUrl", s.baseUrl)
                put("nsfw", s.nsfw)
                put("repo", s.repoName)
                put("mode", "client")
                put("group", "aniyomi")
            })
        }
        return arr.toString()
    }
}
