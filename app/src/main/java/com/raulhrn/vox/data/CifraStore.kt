package com.raulhrn.vox.data

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import com.raulhrn.vox.core.Cifra
import com.raulhrn.vox.core.Setlist
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/** Chord sheets and setlists saved as one small JSON file. Reads and writes happen off the main thread. */
object CifraStore {
    val cifras = mutableStateListOf<Cifra>()
    val setlists = mutableStateListOf<Setlist>()
    val loaded = mutableStateOf(false)

    private lateinit var file: File
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun init(context: Context) {
        if (::file.isInitialized) return
        file = File(context.filesDir, "cifras.json")
        io.execute {
            val data = try {
                if (file.exists()) decode(file.readText()) else Pair(emptyList(), emptyList())
            } catch (_: Exception) {
                Pair(emptyList<Cifra>(), emptyList<Setlist>())
            }
            main.post {
                cifras.clear()
                cifras.addAll(data.first)
                setlists.clear()
                setlists.addAll(data.second)
                loaded.value = true
            }
        }
    }

    fun find(id: String): Cifra? = cifras.firstOrNull { it.id == id }

    fun findSetlist(id: String): Setlist? = setlists.firstOrNull { it.id == id }

    fun upsert(cifra: Cifra) {
        val i = cifras.indexOfFirst { it.id == cifra.id }
        if (i >= 0) {
            if (cifras[i] == cifra) return
            cifras[i] = cifra
        } else {
            cifras.add(0, cifra)
        }
        save()
    }

    /** Deletes a sheet and takes it out of every setlist. */
    fun delete(id: String) {
        cifras.removeAll { it.id == id }
        for (i in setlists.indices) {
            val s = setlists[i]
            if (id in s.items) setlists[i] = s.copy(items = s.items.filter { it != id })
        }
        save()
    }

    fun upsertSetlist(setlist: Setlist) {
        val i = setlists.indexOfFirst { it.id == setlist.id }
        if (i >= 0) {
            if (setlists[i] == setlist) return
            setlists[i] = setlist
        } else {
            setlists.add(0, setlist)
        }
        save()
    }

    fun deleteSetlist(id: String) {
        setlists.removeAll { it.id == id }
        save()
    }

    private fun save() {
        if (!::file.isInitialized) return
        val text = encode(cifras.toList(), setlists.toList())
        io.execute {
            try {
                val tmp = File(file.parentFile, "cifras.json.tmp")
                tmp.writeText(text)
                if (!tmp.renameTo(file)) {
                    file.writeText(text)
                    tmp.delete()
                }
            } catch (_: Exception) {
            }
        }
    }

    fun encode(cifras: List<Cifra>, setlists: List<Setlist>): String {
        val sheets = JSONArray()
        for (c in cifras) {
            sheets.put(
                JSONObject()
                    .put("id", c.id)
                    .put("title", c.title)
                    .put("artist", c.artist)
                    .put("text", c.text)
                    .put("transpose", c.transpose)
                    .put("created", c.createdAt),
            )
        }
        val lists = JSONArray()
        for (s in setlists) {
            lists.put(
                JSONObject()
                    .put("id", s.id)
                    .put("name", s.name)
                    .put("items", JSONArray(s.items))
                    .put("created", s.createdAt),
            )
        }
        return JSONObject().put("version", 1).put("cifras", sheets).put("setlists", lists).toString()
    }

    fun decode(text: String): Pair<List<Cifra>, List<Setlist>> {
        val root = JSONObject(text)
        val cifras = ArrayList<Cifra>()
        val sheets = root.optJSONArray("cifras") ?: JSONArray()
        for (i in 0 until sheets.length()) {
            val o = sheets.getJSONObject(i)
            cifras.add(
                Cifra(
                    id = o.getString("id"),
                    title = o.optString("title", "Sem título"),
                    artist = o.optString("artist", ""),
                    text = o.optString("text", ""),
                    transpose = o.optInt("transpose", 0),
                    createdAt = o.optLong("created", 0L),
                ),
            )
        }
        val setlists = ArrayList<Setlist>()
        val lists = root.optJSONArray("setlists") ?: JSONArray()
        for (i in 0 until lists.length()) {
            val o = lists.getJSONObject(i)
            val arr = o.optJSONArray("items") ?: JSONArray()
            setlists.add(
                Setlist(
                    id = o.getString("id"),
                    name = o.optString("name", "Lista"),
                    items = (0 until arr.length()).map { arr.getString(it) },
                    createdAt = o.optLong("created", 0L),
                ),
            )
        }
        return Pair(cifras, setlists)
    }
}
