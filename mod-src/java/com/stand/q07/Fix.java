package com.stand.q07;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.provider.Settings;
import android.util.Log;
import com.stand.bridge.Ru2Zh;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Fixes layered over the original translator and TTS output (mod 1.8). */
public final class Fix {
    private static final String TAG = "Q07Fix";

    private static final Pattern MASSAGE = Pattern.compile("массаж|массир");
    private static final Pattern MASSAGE_STOP = Pattern.compile("(?<![а-я])(?:убери|убрать|уберите|стоп|хватит|достаточно|прекрати|прекратить|прекратите|перестань|не надо|не нужно|отмени|отменить|заверши|закончи|останови|остановить)(?![а-я])");
    private static final Pattern MASSAGE_ON = Pattern.compile("(?<![а-я])(?:включи|включить|включите|запусти|запустить|сделай|сделать|вруби)(?![а-я])");

    private static final Pattern FAN = Pattern.compile("вентилятор|обдув|продув|скорост[а-я]* (?:вентил|обдув|воздух)|поток[а-я]* воздух");
    private static final Pattern SEAT = Pattern.compile("сиден|кресл|спинк|подушк");
    private static final Pattern VENTILATION_N = Pattern.compile("(?<![а-я])вентиляц[а-я]*");
    private static final Pattern HAS_NUM = Pattern.compile("\\d|(?<![а-я])(?:один|одну|два|две|три|четыре|пять|шесть|семь|восемь|перв|втор|трет|четв[её]рт|пят[ыоуа]|шест[оуа]|седьм|восьм)");
    private static final String[][] ORDINALS = {
            {"(?<![а-я])перв[а-я]*", "1"}, {"(?<![а-я])втор[а-я]*", "2"}, {"(?<![а-я])трет[а-я]*", "3"},
            {"(?<![а-я])четв[её]рт[а-я]*", "4"}, {"(?<![а-я])пят(?:ый|ая|ую|ой|ом|ую|ого)(?![а-я])", "5"},
            {"(?<![а-я])шест(?:ой|ая|ую|ом|ого)(?![а-я])", "6"}, {"(?<![а-я])седьм[а-я]*", "7"},
            {"(?<![а-я])восьм(?:ой|ая|ую|ом|ого)(?![а-я])", "8"}};

    private static final Pattern NAVI = Pattern.compile("навигатор|навигаци|(?<![а-я])карт[ыуа]?(?![а-я])");
    private static final Pattern NAVI_WORDS = Pattern.compile("(?<![а-я])(?:навигатор[а-я]*|навигаци[а-я]*|карт[ыуа]?|яндекс|мне|пожалуйста|давай|приложение)(?![а-я])");
    private static final Pattern NAVI_ON_ONLY = Pattern.compile("(?:включи|включить|включите|открой|открыть|откройте|запусти|запустить|запустите|покажи|вруби)(?:\\s+(?:включи|открой|запусти))?");
    private static final Pattern NAVI_OFF_ONLY = Pattern.compile("(?:выключи|выключить|выключите|отключи|отключить|закрой|закрыть|закройте|заверши|завершить|выйди из|выйти из|останови|убери|сверни|отмени)");

    private static final Pattern NAVI_HOME = Pattern.compile("^(?:(?:включи |запусти |построй |проложи |давай |поехали |едем )?(?:навигаци[а-я]*|навигатор[а-я]*|маршрут[а-я]*)?\\s*(?:до дома|домой)|(?:поехали|едем|вези|отвези|веди) домой)$");
    private static final Pattern NAVI_WORK = Pattern.compile("^(?:(?:включи |запусти |построй |проложи |давай |поехали |едем )?(?:навигаци[а-я]*|навигатор[а-я]*|маршрут[а-я]*)?\\s*(?:до работы|на работу)|(?:поехали|едем|вези|отвези|веди) на работу)$");

    private Fix() {
    }

    static String norm(String s) {
        return s == null ? "" : s.toLowerCase().replace('ё', 'е').trim();
    }

    /** Rewrites a phrase before translation. Returns the phrase to translate. */
    static String preRewrite(String in) {
        String s = norm(in);
        if (s.isEmpty()) {
            return in;
        }
        // "убери / стоп / хватит / не надо массаж" used to switch massage ON
        if (MASSAGE.matcher(s).find() && MASSAGE_STOP.matcher(s).find() && !MASSAGE_ON.matcher(s).find()) {
            String r = MASSAGE_STOP.matcher(s).replaceAll("выключи").replaceAll("\\s+", " ").trim();
            if (!r.startsWith("выключи")) {
                r = "выключи " + r.replaceFirst("(?<![а-я])выключи(?![а-я])", "").replaceAll("\\s+", " ").trim();
            }
            return r;
        }
        boolean seat = SEAT.matcher(s).find();
        // "вентиляция на 3" without a seat is the climate fan
        if (!seat && !MASSAGE.matcher(s).find() && VENTILATION_N.matcher(s).find() && HAS_NUM.matcher(s).find()) {
            s = VENTILATION_N.matcher(s).replaceAll("вентилятор");
        }
        // "обдув на третью скорость" -> "обдув на 3 скорость"
        if (!seat && FAN.matcher(s).find()) {
            for (String[] o : ORDINALS) {
                s = s.replaceAll(o[0], o[1]);
            }
        }
        return s;
    }

    static String postFix(String zh) {
        if (zh == null) {
            return null;
        }
        // be explicit about the climate fan, like the stock phrasing "空调风量调到N档"
        if (zh.startsWith("风量")) {
            return "空调" + zh;
        }
        return zh;
    }

    public static String[] ru2zhAll(String in, int zone) {
        String phrase = in;
        try {
            phrase = preRewrite(in);
            if (!phrase.equals(in)) {
                Log.i(TAG, "rewrite [" + in + "] -> [" + phrase + "]");
            }
        } catch (Throwable th) {
            Log.e(TAG, "preRewrite", th);
            phrase = in;
        }
        String[] out = Ru2Zh.ru2zhAll0(phrase, zone);
        try {
            if (out == null) {
                String s = norm(phrase);
                // "включи навигатор", "навигация", "открой карты" -> map / Yandex Navigator
                if (NAVI_HOME.matcher(s).find()) {
                    return new String[]{"导航回家"};
                }
                if (NAVI_WORK.matcher(s).find()) {
                    return new String[]{"导航去公司"};
                }
                // only plain "включи навигатор" / "выключи навигацию" / "навигатор": nothing else in the phrase
                if (NAVI.matcher(s).find()) {
                    String rest = NAVI_WORDS.matcher(s).replaceAll(" ").trim();
                    if (rest.isEmpty()) {
                        return new String[]{"打开地图"};
                    }
                    if (NAVI_OFF_ONLY.matcher(rest).matches()) {
                        return new String[]{"退出导航"};
                    }
                    if (NAVI_ON_ONLY.matcher(rest).matches()) {
                        return new String[]{"打开地图"};
                    }
                }
                return null;
            }
            for (int i = 0; i < out.length; i++) {
                out[i] = postFix(out[i]);
            }
        } catch (Throwable th) {
            Log.e(TAG, "postFix", th);
        }
        return out;
    }

    /** Assistant voice on the same audio channel as the stock assistant (voice volume, no music ducking). */
    public static AudioTrack newTrack(int rate, int bufferBytes) {
        int usage = 18;
        int contentType = 4;
        try {
            Context ctx = Q07Bridge.appContext();
            if (ctx != null) {
                usage = Settings.Global.getInt(ctx.getContentResolver(), "stand_tts_usage", 18);
                contentType = Settings.Global.getInt(ctx.getContentResolver(), "stand_tts_content", 4);
            }
        } catch (Throwable th) {
        }
        if (usage > 0) {
            try {
                AudioAttributes aa = new AudioAttributes.Builder().setContentType(contentType).setUsage(usage).build();
                AudioFormat af = new AudioFormat.Builder().setSampleRate(rate).setEncoding(2).setChannelMask(4).build();
                AudioTrack t = new AudioTrack(aa, af, bufferBytes, 1, 0);
                if (t.getState() == 1) {
                    return t;
                }
                t.release();
                Log.w(TAG, "usage " + usage + " track not initialized, fallback to music stream");
            } catch (Throwable th) {
                Log.w(TAG, "usage " + usage + " failed, fallback to music stream: " + th);
            }
        }
        return new AudioTrack(3, rate, 4, 2, bufferBytes, 1);
    }
}
