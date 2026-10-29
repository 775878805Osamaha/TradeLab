package com.example.feature.chart

import android.content.SharedPreferences
import com.example.feature.chart.model.IndicatorSettings

/** Versioned primitive preferences; invalid or missing values use safe defaults. */
internal object ChartWorkspaceSettings {
    fun save(prefs: SharedPreferences, key: String, s: IndicatorSettings) {
        val periods=listOf(s.smaPeriod,s.emaPeriod,s.bollingerPeriod,s.rsiPeriod,s.macdFast,s.macdSlow,s.macdSignal,s.atrPeriod)
        val enabled=listOf(s.isSmaEnabled,s.isEmaEnabled,s.isBollingerEnabled,s.isVwapEnabled,s.isRsiEnabled,s.isMacdEnabled,s.isAtrEnabled)
        prefs.edit().putString(key,"1|${periods.joinToString(",")}|${s.bollingerStdDev}|${enabled.joinToString(",")}").apply()
    }
    fun load(prefs: SharedPreferences,key: String="indicators"): IndicatorSettings = decode(prefs.getString(key,null))
    fun decode(raw: String?): IndicatorSettings {
        val fallback=IndicatorSettings(isEmaEnabled=false)
        return runCatching {
            val fields=raw!!.split('|');require(fields.size==4 && fields[0]=="1")
            val p=fields[1].split(',').map(String::toInt)
            val d=fields[2].toDouble()
            val b=fields[3].split(',').map { require(it=="true"||it=="false");it=="true" }
            require(p.size==8 && p.all { it in 2..500 } && p[4]<p[5] && d.isFinite() && d in 0.1..10.0 && b.size==7)
            IndicatorSettings(p[0],b[0],p[1],b[1],p[2],d,b[2],b[3],p[3],b[4],p[4],p[5],p[6],b[5],p[7],b[6])
        }.getOrDefault(fallback)
    }
}
