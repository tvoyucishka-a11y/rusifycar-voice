package com.stand.q07;

import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.RemoteException;
import android.util.Log;

/**
 * Steering-wheel voice key listener (CaKeyService).
 * Self-healing: retries without a time limit, re-registers when the key service dies or
 * restarts (linkToDeath + periodic check), so the wheel button does not get "lost".
 */
public final class CaKey {
    public static final int KEYCODE_VOICE_ASSIST = 231;
    private static final String LSN_DESCRIPTOR = "com.incall.sdakeyservice.ICaKeyEventListener";
    private static final String MGR_DESCRIPTOR = "com.incall.sdakeyservice.ICaKeyManager";
    private static final String SERVICE_NAME = "com.incall.sdakeyservice.CaKeyService";
    private static final String TAG = "Q07CaKey";
    private static final int TXN_registerKeyEventListener = 1;
    private static final long RETRY_MS = 2000L;
    private static final long CHECK_MS = 10000L;

    private static volatile OnVoiceKey callback;
    private static volatile IBinder boundService;
    private static volatile boolean started;
    private static final Object WAKE = new Object();
    private static Listener listener;

    public interface OnVoiceKey {
        void onPress();
    }

    public static void register(OnVoiceKey onVoiceKey) {
        callback = onVoiceKey;
        synchronized (CaKey.class) {
            if (started) {
                return;
            }
            started = true;
        }
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                watch();
            }
        }, "q07-cakey");
        t.setDaemon(true);
        t.start();
    }

    private static void watch() {
        int fails = 0;
        while (true) {
            IBinder cur = boundService;
            if (cur == null || !cur.isBinderAlive()) {
                boundService = null;
                try {
                    IBinder service = getService(SERVICE_NAME);
                    if (service != null && registerWith(service)) {
                        fails = 0;
                    } else if (fails++ % 30 == 0) {
                        Log.w(TAG, "voice-key service not available yet, retrying");
                    }
                } catch (Throwable th) {
                    if (fails++ % 30 == 0) {
                        Log.w(TAG, "register attempt failed: " + th);
                    }
                }
            }
            synchronized (WAKE) {
                try {
                    WAKE.wait(boundService == null ? RETRY_MS : CHECK_MS);
                } catch (InterruptedException e) {
                }
            }
        }
    }

    private static boolean registerWith(final IBinder service) throws RemoteException {
        if (listener == null) {
            listener = new Listener();
        }
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(MGR_DESCRIPTOR);
            data.writeStrongBinder(listener);
            boolean ok = service.transact(TXN_registerKeyEventListener, data, reply, 0);
            reply.readException();
            try {
                service.linkToDeath(new IBinder.DeathRecipient() {
                    @Override
                    public void binderDied() {
                        Log.w(TAG, "voice-key service died, re-registering");
                        if (boundService == service) {
                            boundService = null;
                        }
                        synchronized (WAKE) {
                            WAKE.notifyAll();
                        }
                    }
                }, 0);
            } catch (Throwable th) {
                Log.w(TAG, "linkToDeath: " + th);
            }
            boundService = service;
            Log.i(TAG, "voice-key listener registered (transact=" + ok + ")");
            return true;
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private static IBinder getService(String name) throws Throwable {
        return (IBinder) Class.forName("android.os.ServiceManager").getMethod("getService", String.class).invoke(null, name);
    }

    private static final class Listener extends Binder implements IInterface {
        Listener() {
            attachInterface(this, LSN_DESCRIPTOR);
        }

        @Override
        public IBinder asBinder() {
            return this;
        }

        @Override
        protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            switch (code) {
                case 1: {
                    data.enforceInterface(LSN_DESCRIPTOR);
                    int key = data.readInt();
                    int action = data.readInt();
                    if (reply != null) {
                        reply.writeNoException();
                    }
                    if (key == KEYCODE_VOICE_ASSIST && action == 0) {
                        fire();
                    }
                    return true;
                }
                case 2:
                    data.enforceInterface(LSN_DESCRIPTOR);
                    data.readInt();
                    data.readInt();
                    if (reply != null) {
                        reply.writeNoException();
                    }
                    return true;
                case INTERFACE_TRANSACTION:
                    if (reply != null) {
                        reply.writeString(LSN_DESCRIPTOR);
                    }
                    return true;
                default:
                    return super.onTransact(code, data, reply, flags);
            }
        }

        private void fire() {
            try {
                Log.i(TAG, "voice key 231 pressed -> wake");
                OnVoiceKey cb = callback;
                if (cb != null) {
                    cb.onPress();
                }
            } catch (Throwable th) {
                Log.e(TAG, "fire", th);
            }
        }
    }

    private CaKey() {
    }
}
