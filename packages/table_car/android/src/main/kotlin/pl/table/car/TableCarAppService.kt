package pl.table.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/** Wejście Android Auto: tworzy sesję z ekranem bieżącego kursu. */
class TableCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        // Wersja deweloperska przyjmuje każdy host (emulator DHU), wydanie tylko zaufane hosty Google.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = TableCarSession()
}

class TableCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = CourseScreen(carContext)
}

/**
 * Bieżący kurs na ekranie samochodu: adres, klient, płatność i dwa duże przyciski,
 * „Nawiguj” (nawigacja w aucie) i „Zadzwoń”. Bez kursu: miejsce w kolejce.
 * Zmiana etapu kursu zostaje na telefonie, żeby w czasie jazdy nie klikać w szczegóły.
 */
class CourseScreen(carContext: CarContext) : Screen(carContext) {
    private val listener: () -> Unit = { invalidate() }

    init {
        CourseStore.load(carContext)
        CourseStore.listen(listener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CourseStore.unlisten(listener)
            }
        })
    }

    override fun onGetTemplate(): Template {
        val state = CourseStore.state
        val course = state?.optJSONObject("course")
        if (course == null) {
            val status = state?.optString("status").orEmpty()
                .ifEmpty { "Otwórz Table for employees na telefonie i zacznij zmianę." }
            return MessageTemplate.Builder(status)
                .setTitle("Table · Dostawy")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }

        val address = course.optString("address")
        val phone = course.optString("phone")
        val stage = listOf(course.optString("promised"), course.optString("stage"))
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
        val details = listOf(course.optString("items"), course.optString("note"))
            .filter { it.isNotEmpty() }
            .joinToString(" · ")

        val navigate = Action.Builder()
            .setTitle("Nawiguj")
            .setOnClickListener { navigate(address) }
        if (carContext.carAppApiLevel >= 4) navigate.setFlags(Action.FLAG_PRIMARY)

        val pane = Pane.Builder()
            .addRow(Row.Builder().setTitle(address).addText(stage.ifEmpty { " " }).build())
            .addRow(Row.Builder().setTitle(course.optString("customer")).addText(phone).build())
            .addRow(Row.Builder().setTitle(course.optString("payment")).addText(details.ifEmpty { " " }).build())
            .addAction(navigate.build())
            .addAction(
                Action.Builder()
                    .setTitle("Zadzwoń")
                    .setOnClickListener { call(phone) }
                    .build(),
            )
            .build()

        val next = state.optInt("next")
        val title = "Kurs #${course.optInt("number")}" + if (next > 0) " (+$next)" else ""
        return PaneTemplate.Builder(pane)
            .setTitle(title)
            .setHeaderAction(Action.APP_ICON)
            .build()
    }

    private fun navigate(address: String) {
        val uri = Uri.parse("geo:0,0?q=" + Uri.encode(address))
        runCatching { carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri)) }
            .onFailure { CarToast.makeText(carContext, "Nie udało się otworzyć nawigacji", CarToast.LENGTH_LONG).show() }
    }

    private fun call(phone: String) {
        val uri = Uri.parse("tel:" + phone.replace(" ", ""))
        runCatching { carContext.startCarApp(Intent(Intent.ACTION_DIAL, uri)) }
            .onFailure { CarToast.makeText(carContext, "Nie udało się zadzwonić", CarToast.LENGTH_LONG).show() }
    }
}
