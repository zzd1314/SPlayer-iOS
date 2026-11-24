package com.splayer.next

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.splayer.next.ui.SPlayerApp
import com.splayer.next.ui.theme.SPlayerTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SPlayerTheme {
                SPlayerApp()
            }
        }
    }
}
