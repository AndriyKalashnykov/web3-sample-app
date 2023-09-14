import React from 'react'
import ReactDOM from 'react-dom/client'
import '@/styles/main.css'
import App from './App'
import {store} from './store'
import {Provider} from 'react-redux'
import {ThemeProvider} from '@mui/material/styles'
import {theme} from './theme'
import {DevSupport} from "@react-buddy/ide-toolbox";
import {ComponentPreviews, useInitial} from "@/dev";

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <ThemeProvider theme={theme}>
            <Provider store={store}>
                <DevSupport ComponentPreviews={ComponentPreviews}
                            useInitialHook={useInitial}
                >
                    <App/>
                </DevSupport>
            </Provider>
        </ThemeProvider>
    </React.StrictMode>,
)
