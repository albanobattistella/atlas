/*
* Copyright (c) 2014-2018 Atlas Maps Developers
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <https://www.gnu.org/licenses/>.
*
* Inspired from https://gitlab.gnome.org/GNOME/gnome-clocks/blob/master/src/geocoding.vala
*/

namespace Atlas {

    private enum AccuracyLevel {
        COUNTRY = 1,
        CITY = 4,
        STREET = 6,
        EXACT = 8,
    }

    [DBus (name = "org.freedesktop.GeoClue2.Manager")]
    private interface Manager : Object {
        public abstract async void get_client (out string client_path) throws Error;
    }

    [DBus (name = "org.freedesktop.GeoClue2.Location")]
    public interface Location : Object {
        public abstract double latitude { get; }
        public abstract double longitude { get; }
        public abstract double accuracy { get; }
        public abstract string description { owned get; }
    }

    [DBus (name = "org.freedesktop.GeoClue2.Client")]
    private interface Client : Object {
        public abstract ObjectPath location { owned get; }
        public abstract string desktop_id { owned get; set; }
        public abstract uint distance_threshold { get; set; }
        public abstract uint requested_accuracy_level { get; set; }

        public signal void location_updated (ObjectPath old_path, ObjectPath new_path);

        public abstract async void start () throws Error;

        // This function belongs to the Geoclue interface, however it is not used here
        // public abstract async void stop () throws IOError;
    }

    public class GeoClue {

        public signal void location_changed (Atlas.Location loc);

        private const string DESKTOP_ID = Build.PROJECT_NAME;

        private Manager manager;
        private Client client;
        private string country_code;
        private double minimal_distance;
        public Location? geo_location { get; private set; default = null; }

        public GeoClue () {
            country_code = null;
            minimal_distance = 1000.0d;
        }

        public async void seek () {
            string client_path = null;

            try {
                manager = yield Bus.get_proxy (GLib.BusType.SYSTEM,
                                                "org.freedesktop.GeoClue2",
                                                "/org/freedesktop/GeoClue2/Manager");
            } catch (IOError io) {
                warning ("Failed to connect to GeoClue2 Manager service");
                return;
            }

            try {
                yield manager.get_client (out client_path);
            } catch (Error io) {
                warning ("Failed to connect to GeoClude2 service");
                return;
            }

            if (client_path == null) {
                warning ("Client path is not set");
                return;
            }

            try {
                client = yield Bus.get_proxy (GLib.BusType.SYSTEM,
                                                "org.freedesktop.GeoClue2",
                                                client_path);
            } catch (IOError io) {
                warning ("Failed to connect to GeoClude2 Client");
                return;
            }

            client.desktop_id = DESKTOP_ID;
            client.requested_accuracy_level = AccuracyLevel.EXACT;

            client.location_updated.connect ((old_path, new_path) => {
                on_location_updated.begin (old_path, new_path, (obj, res) => {
                    on_location_updated.end (res);
                });
            });

            try {
                yield client.start ();
            } catch (Error io) {
                warning ("Failed to start client");
                return;
            }
        }

        public async void on_location_updated (ObjectPath old_path, ObjectPath new_path) {
            try {
                geo_location = yield Bus.get_proxy (GLib.BusType.SYSTEM,
                                                        "org.freedesktop.GeoClue2",
                                                        new_path);

                if (geo_location != null) {
                    location_changed (geo_location);
                }

            } catch (IOError io) {
                warning ("Failed to connect to GeoClue2 Location service");
                return;
            }
        }
    }
}
