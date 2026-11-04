import com.raulhrn.vox.core.Exercise
import com.raulhrn.vox.core.Exercises
import com.raulhrn.vox.core.SecondVoiceLessons
import com.raulhrn.vox.core.Studies
import com.raulhrn.vox.core.Tips
import java.io.File

/** Writes the Kotlin content as JSON, the single source of truth for both apps. */
fun main(args: Array<String>) {
    val out = File(args.firstOrNull() ?: "content.json")
    val json = obj(
        "exercises" to arr(Exercises.all.map { exercise(it) }),
        "studies" to arr(Studies.all.map { obj("title" to str(it.title), "summary" to str(it.summary), "body" to str(it.body)) }),
        "tips" to arr(Tips.all.map { str(it) }),
        "lessons" to arr(
            SecondVoiceLessons.all.map {
                obj(
                    "mode" to str(it.mode.name),
                    "whenToUse" to str(it.whenToUse),
                    "howTo" to arr(it.howTo.map { s -> str(s) }),
                    "exerciseId" to str(it.exerciseId),
                )
            },
        ),
        "lessonExample" to obj(
            "pattern" to arr(SecondVoiceLessons.example.map { it.toString() }),
            "beats" to arr(SecondVoiceLessons.exampleBeats.map { it.toString() }),
        ),
    )
    out.parentFile?.mkdirs()
    out.writeText(json + "\n")
    println("wrote ${out.path}")
}

private fun exercise(e: Exercise): String = obj(
    "id" to str(e.id),
    "title" to str(e.title),
    "category" to str(e.category),
    "summary" to str(e.summary),
    "steps" to arr(e.steps.map { str(it) }),
    "kind" to str(e.kind.name),
    // A rest is written as null.
    "pattern" to arr(e.pattern.map { if (it == Exercise.REST) "null" else it.toString() }),
    "beats" to (e.beats?.let { b -> arr(b.map { it.toString() }) } ?: "null"),
    "bpm" to e.bpm.toString(),
    "legato" to e.legato.toString(),
    "harmony" to (e.harmony?.let { str(it.name) } ?: "null"),
    "backing" to (e.backing?.let { str(it.name) } ?: "null"),
    "backingVoices" to e.backingVoices.toString(),
    "backingPart" to e.backingPart.toString(),
    "rootStep" to e.rootStep.toString(),
    "minutes" to e.minutes.toString(),
    "needsHeadphones" to e.needsHeadphones.toString(),
)

private fun obj(vararg fields: Pair<String, String>) =
    fields.joinToString(",\n", "{\n", "\n}") { (k, v) -> "  ${str(k)}: ${v.replace("\n", "\n  ")}" }

private fun arr(items: List<String>) = if (items.isEmpty()) "[]" else items.joinToString(", ", "[", "]")

private fun str(s: String): String {
    val b = StringBuilder("\"")
    for (ch in s) {
        when (ch) {
            '"' -> b.append("\\\"")
            '\\' -> b.append("\\\\")
            '\n' -> b.append("\\n")
            '\t' -> b.append("\\t")
            else -> if (ch < ' ') b.append("\\u%04x".format(ch.code)) else b.append(ch)
        }
    }
    return b.append('"').toString()
}
