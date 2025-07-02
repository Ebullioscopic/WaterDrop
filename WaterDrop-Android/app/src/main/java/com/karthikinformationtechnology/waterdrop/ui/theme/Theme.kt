package com.karthikinformationtechnology.waterdrop.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = NothingWhite,
    secondary = NothingLightGray,
    tertiary = NothingAccent,
    background = NothingBlack,
    surface = NothingDarkGray,
    onPrimary = NothingBlack,
    onSecondary = NothingWhite,
    onTertiary = NothingWhite,
    onBackground = NothingWhite,
    onSurface = NothingWhite,
    error = NothingRed,
    onError = NothingWhite
)

private val LightColorScheme = lightColorScheme(
    primary = NothingBlack,
    secondary = NothingGray,
    tertiary = NothingAccent,
    background = NothingWhite,
    surface = NothingLightGray,
    onPrimary = NothingWhite,
    onSecondary = NothingBlack,
    onTertiary = NothingBlack,
    onBackground = NothingBlack,
    onSurface = NothingBlack,
    error = NothingRed,
    onError = NothingWhite
)

@Composable
fun WaterDropTheme(
    darkTheme: Boolean = true, // Always use dark theme for Nothing aesthetic
    // Dynamic color is available on Android 12+
    dynamicColor: Boolean = false, // Disable dynamic colors for consistent branding
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = DarkColorScheme, // Force dark theme
        typography = Typography,
        content = content
    )
}