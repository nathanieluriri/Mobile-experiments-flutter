package ng.com.uriri.quire

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "Not now" on a notice: it goes, and nothing opens. */
class NoticeDismissed : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(ID, 0)
        context.getSystemService(NotificationManager::class.java).cancel(id)
    }

    companion object {
        const val ID = "id"
    }
}
