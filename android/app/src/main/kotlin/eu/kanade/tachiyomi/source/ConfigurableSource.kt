package eu.kanade.tachiyomi.source

import eu.kanade.tachiyomi.PreferenceScreen

interface ConfigurableSource : Source {

    fun setupPreferenceScreen(screen: PreferenceScreen)
}
