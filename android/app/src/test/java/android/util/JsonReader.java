package android.util;

import java.io.Closeable;
import java.io.IOException;
import java.io.Reader;

// The JVM stand-in for Android's JsonReader, which was taken from gson's: same tokens, same strict mode.
public final class JsonReader implements Closeable {
    private final com.google.gson.stream.JsonReader reader;

    public JsonReader(Reader in) {
        reader = new com.google.gson.stream.JsonReader(in);
    }

    public void setLenient(boolean lenient) { reader.setLenient(lenient); }
    public boolean isLenient() { return reader.isLenient(); }
    public JsonToken peek() throws IOException { return JsonToken.valueOf(reader.peek().name()); }
    public void beginObject() throws IOException { reader.beginObject(); }
    public void endObject() throws IOException { reader.endObject(); }
    public void beginArray() throws IOException { reader.beginArray(); }
    public void endArray() throws IOException { reader.endArray(); }
    public boolean hasNext() throws IOException { return reader.hasNext(); }
    public String nextName() throws IOException { return reader.nextName(); }
    public String nextString() throws IOException { return reader.nextString(); }
    public boolean nextBoolean() throws IOException { return reader.nextBoolean(); }
    public void nextNull() throws IOException { reader.nextNull(); }
    @Override public void close() throws IOException { reader.close(); }
}
