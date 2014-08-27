/*
 * vera-plugin-tint2 - tint2 plugin for vera
 * Copyright (C) 2014  Eugenio "g7" Paolantonio and the Semplice Project
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *     Eugenio "g7" Paolantonio <me@medesimo.eu>
*/

using Vera;

namespace Tint2Plugin {

	public class Plugin : Peas.ExtensionBase, VeraPlugin {

		private string HOME = Environment.get_home_dir();

		public XlibDisplay display;
		public Settings settings;
		
		private string? get_window_name(X.Window window) {
			/**
			 * Returns the window name given an X.Window by looking
			 * at its WM_NAME property.
			*/
			
			X.Atom type;
			int form;
			ulong length, remain;
			void* result;
						
			if (display.display.get_window_property(
				window,
				display.display.intern_atom("WM_NAME", false),
				0,
				1024,
				false,
				X.XA_STRING,
				out type,
				out form,
				out length,
				out remain,
				out result
			) == 1) {
				/* Fail, skipping */
				return null;
			}
						
			return (string)result;
		}
					
		private void stick() {
			/**
			 * Sometimes the panel will not stick on every desktop because
			 * the WM may be fully initialized after the panel startup.
			 * This method ensures that the panel will be sticky on every
			 * desktop regardless of the state it was before.
			*/
			
			int64[] struts = { 0xFFFFFFFF };
			
			X.Atom type;
			int form;
			ulong length, remain;
			void* list_data;
			
			/* Get window list */			
			if (display.display.get_window_property(
				display.xrootwindow,
				display.display.intern_atom("_NET_CLIENT_LIST", false),
				0,
				1024,
				false,
				X.XA_WINDOW,
				out type,
				out form,
				out length,
				out remain,
				out list_data
			) == 1) {
				/* Fail, skipping */
				return;
			}
			
			unowned X.Window[] list = (X.Window[])list_data;
			
			for (int i=0; i < length; i++) {
				/* Search for tint2 */
				if (this.get_window_name(list[i]) == "tint2") {
					/* Change desktop property */
					display.display.change_property(
						list[i],
						display.display.intern_atom("_NET_WM_DESKTOP", false),
						X.XA_CARDINAL,
						32,
						X.PropMode.Replace,
						(uchar[])struts,
						1
					);
				}
			}
			
		}
				
		
		private void on_process_terminated(Pid pid, int status) {
			/**
			 * Fired when the process pid has been terminated.
			 */
			
			debug("Pid %s terminated.", pid.to_string());
			
			Process.close_pid(pid);
			
			if (status > 1)
				this.startup(StartupPhase.PANEL);
		}

		public void init(Display display) {
			/**
			 * Initializes the plugin.
			 */
			
			try {
				this.display = (XlibDisplay)display;
					
				this.settings = new Settings("org.semplicelinux.vera.tint2");

			} catch (Error ex) {
				error("Unable to load plugin settings.");
			}

			
		}
		
		public void startup(StartupPhase phase) {
			/**
			 * Called by vera when doing the startup.
			 */
			
			if (phase == StartupPhase.PANEL) {
				/* Launch tint2. */
				Pid pid;
				
				try {
				
					if (this.settings.get_boolean("first-start")) {
						/* First start */
						DateTime local = new DateTime.now_local();
						if (local.format("%p") != "") {
							/* This timezone uses AM/PM, properly
							 * set it in the panel's secondary_configuration */
							
							File secondary_config = File.new_for_path(
								Path.build_filename(this.HOME, ".config/tint2", "secondary_config")
							);
							
							File directory = secondary_config.get_parent();
							if (!directory.query_exists())
								directory.make_directory_with_parents();
							
							FileIOStream io_stream;
							if (!secondary_config.query_exists())
								io_stream = secondary_config.create_readwrite(FileCreateFlags.PRIVATE);
							else
								io_stream = secondary_config.open_readwrite();
							
							FileOutputStream stream = io_stream.output_stream as FileOutputStream;
							
							size_t written;
							stream.write_all("time1_format = %I:%M %p\npanel_items = TSC\n".data, out written);
							stream.close();
						}
						
						this.settings.set_boolean("first-start", false);
						
					}
				
				} catch (Error e) {
					warning("Unable to set-up the secondary_config: %s", e.message); 
				}
				
				/* Check for the configuration_file */
				string configuration_file = this.settings.get_string("configuration-file");
				if (!FileUtils.test(configuration_file, FileTest.EXISTS))
					/* It doesn't exist, use the default configuration file */
					configuration_file = "/etc/xdg/tint2/tint2rc";
				
				try {
					Process.spawn_async(
						this.HOME,
						{ "tint2", "-c", configuration_file },
						Environ.get(),
						SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
						null,
						out pid
					);
										
					ChildWatch.add(pid, this.on_process_terminated);
				} catch (SpawnError e) {
					warning(e.message);
				}
				
				/* A 3 second wait should be enough */
				Timeout.add_seconds(
					3,
					() => {
						this.stick();
						
						return false;
					}
				);
			}
			
		}
		
		/* FIXME */
		public void shutdown() {}
		

	}
}

[ModuleInit]
public void peas_register_types(GLib.TypeModule module)
{
	Peas.ObjectModule objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(VeraPlugin), typeof(Tint2Plugin.Plugin));
}
