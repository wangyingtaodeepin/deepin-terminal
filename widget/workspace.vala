/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 * -*- coding: utf-8 -*-
 *
 * Copyright (C) 2011 ~ 2016 Deepin, Inc.
 *               2011 ~ 2016 Wang Yong
 *
 * Author:     Wang Yong <wangyong@deepin.com>
 * Maintainer: Wang Yong <wangyong@deepin.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */ 

using Animation;
using Gee;
using Gtk;
using Utils;
using Widgets;

namespace Widgets {
    public class Workspace : Gtk.Overlay {
		public WorkspaceManager workspace_manager;
        public AnimateTimer remote_panel_hide_timer;
        public AnimateTimer remote_panel_show_timer;
        public AnimateTimer theme_panel_hide_timer;
        public AnimateTimer theme_panel_show_timer;
        public ArrayList<Term> term_list;
        public RemotePanel? remote_panel;
        public SearchPanel? search_panel;
        public Term? terminal_before_popup;
        public Term? focus_terminal;
        public ThemePanel? theme_panel;
        public int PANED_HANDLE_SIZE = 1;
        public int hide_slider_interval = 500;
        public int hide_slider_start_x;
        public int index;
        public int show_slider_interval = 500;
        public int show_slider_start_x;
        
        public signal void change_title(int index, string dir);
        public signal void exit(int index);
        public signal void highlight_tab(int index);
        
        public Workspace(int workspace_index, string? work_directory, WorkspaceManager manager) {
            index = workspace_index;
            term_list = new ArrayList<Term>();
			workspace_manager = manager;
            
			remote_panel_show_timer = new AnimateTimer(AnimateTimer.ease_out_quint, show_slider_interval);
			remote_panel_show_timer.animate.connect(remote_panel_show_animate);

			remote_panel_hide_timer = new AnimateTimer(AnimateTimer.ease_in_quint, hide_slider_interval);
			remote_panel_hide_timer.animate.connect(remote_panel_hide_animate);

			theme_panel_show_timer = new AnimateTimer(AnimateTimer.ease_out_quint, show_slider_interval);
			theme_panel_show_timer.animate.connect(theme_panel_show_animate);

			theme_panel_hide_timer = new AnimateTimer(AnimateTimer.ease_in_quint, hide_slider_interval);
			theme_panel_hide_timer.animate.connect(theme_panel_hide_animate);
            
            Term term = new_term(true, work_directory);
            
            add(term);
        }
        
        public Term new_term(bool first_term, string? work_directory) {
            Term term = new Widgets.Term(first_term, work_directory, workspace_manager);
            term.change_title.connect((term, dir) => {
                    change_title(index, dir);
                });
			term.highlight_tab.connect((term) => {
					highlight_tab(index);
				});
            term.exit.connect((term) => {
                    remove_all_panel();
                    close_term(term);
                });
            term.term.button_press_event.connect((w, e) => {
                    remove_search_panel();
					hide_theme_panel();
					hide_remote_panel();
                    
                    update_focus_terminal(term);
                    
                    return false;
                });
            
            term_list.add(term);
            
            return term;
        }
        
        public bool has_active_term() {
            foreach (Term term in term_list) {
                if (term.has_foreground_process()) {
                    return true;
                }
            }
            
            return false;
        }
        
        public void close_focus_term() {
            Term focus_term = get_focus_term(this);
            if (focus_term.has_foreground_process()) {
                ConfirmDialog dialog = Widgets.create_running_confirm_dialog((Widgets.ConfigWindow) focus_term.get_toplevel());
                dialog.confirm.connect((d) => {
                        close_term(focus_term);
                    });
            } else {
                close_term(focus_term);
            }
        }
		
		public void toggle_select_all() {
			Term focus_term = get_focus_term(this);
			focus_term.toggle_select_all();
		}
		
		public void close_other_terms() {
			Term focus_term = get_focus_term(this);
			
			bool has_active_process = false;
			foreach (Term term in term_list) {
				if (term != focus_term) {
				    if (term.has_foreground_process()) {
				    	has_active_process = true;
				    	
				    	break;
				    }
				}
			}
			
			if (has_active_process) {
                ConfirmDialog dialog = Widgets.create_running_confirm_dialog((Widgets.ConfigWindow) focus_term.get_toplevel());
				dialog.confirm.connect((d) => {
						close_term_except(focus_term);
					});
			} else {
				close_term_except(focus_term);
			}
		}
		
		public void close_term_except(Term except_term) {
			// We need remove term from it's parent before remove all children from workspace.
			Widget parent_widget = except_term.get_parent();
            ((Container) parent_widget).remove(except_term);
			
			// Destory all other terminals, wow! ;)
			foreach (Widget w in get_children()) {
				w.destroy();
			}
			
			// Re-parent except terminal.
			term_list = new ArrayList<Term>();
			term_list.add(except_term);
			add(except_term);
		}
        
        public void close_term(Term term) {
            Container parent_widget = term.get_parent();
            parent_widget.remove(term);
            term.destroy();
            term_list.remove(term);
            
            clean_unused_parent(parent_widget);
        }
        
        public void clean_unused_parent(Gtk.Container container) {
            if (container.get_children().length() == 0) {
                if (container.get_type().is_a(typeof(Workspace))) {
                    exit(index);
                } else {
                    Container parent_widget = container.get_parent();
                    parent_widget.remove(container);
                    container.destroy();
                    
                    clean_unused_parent(parent_widget);
                }
            } else {
                if (container.get_type().is_a(typeof(Paned))) {
					var first_child = container.get_children().nth_data(0);
					if (first_child.get_type().is_a(typeof(Paned))) {
						((Term) ((Paned) first_child).get_children().nth_data(0)).focus_term();
					} else {
						((Term) first_child).focus_term();
					}
                }
            }
        }
        
        public Term get_focus_term(Container container) {
            Widget focus_child = container.get_focus_child();
            if (terminal_before_popup != null) {
                return terminal_before_popup;
            } else if (focus_child.get_type().is_a(typeof(Term))) {
                return (Term) focus_child;
            } else {
                return get_focus_term((Container) focus_child);
            }
        }
        
        public void split_vertical() {
            split(Gtk.Orientation.HORIZONTAL);
            
            update_focus_terminal(get_focus_term(this));
        }
            
        public void split_horizontal() {
            split(Gtk.Orientation.VERTICAL);
            
            update_focus_terminal(get_focus_term(this));
        }
        
        public void split(Orientation orientation) {
            Term focus_term = get_focus_term(this);
            
            Gtk.Allocation alloc;
            focus_term.get_allocation(out alloc);
            
            Widget parent_widget = focus_term.get_parent();
            ((Container) parent_widget).remove(focus_term);
            Paned paned = new Paned(orientation);
			paned.draw.connect((w, cr) => {
					Utils.propagate_draw(paned, cr);
					
                    Gtk.Allocation rect;
                    w.get_allocation(out rect);
					
					int pos = paned.get_position();
					if (pos != 0 && paned.get_child1() != null && paned.get_child2() != null) {
						cr.set_operator(Cairo.Operator.OVER);
						Widgets.ConfigWindow parent_window = (Widgets.ConfigWindow) w.get_toplevel();
                        Gdk.RGBA paned_background_color;
						try {
                            paned_background_color = Utils.hex_to_rgba(
                                parent_window.config.config_file.get_string("theme", "background"),
                                parent_window.config.config_file.get_double("general", "opacity"));
                            Utils.set_context_color(cr, paned_background_color);
						} catch (GLib.KeyFileError e) {
							print("Workapce split: %s\n", e.message);
						}
					
						if (orientation == Gtk.Orientation.HORIZONTAL) {
							Draw.draw_rectangle(cr, pos, 0, 1, rect.height);
						} else {
							Draw.draw_rectangle(cr, 0, pos, rect.width, 1);
						}
					
						cr.set_source_rgba(1, 1, 1, 0.1);
						if (orientation == Gtk.Orientation.HORIZONTAL) {
							Draw.draw_rectangle(cr, pos, 0, 1, rect.height);
						} else {
							Draw.draw_rectangle(cr, 0, pos, rect.width, 1);
						}
					}
                    
                    return true;
                });
            Term term = new_term(false, focus_term.current_dir);
            paned.pack1(focus_term, true, false);
            paned.pack2(term, true, false);
            
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                paned.set_position(alloc.width / 2); 
            } else {
                paned.set_position(alloc.height / 2); 
            }
                
            if (parent_widget.get_type().is_a(typeof(Workspace))) {
                ((Workspace) parent_widget).add(paned);
            } else if (parent_widget.get_type().is_a(typeof(Paned))) {
                if (focus_term.is_first_term) {
                    ((Paned) parent_widget).pack1(paned, true, false);
                } else {
                    focus_term.is_first_term = true;
                    ((Paned) parent_widget).pack2(paned, true, false);
                }
                
            }
            
            this.show_all();
        }
        
        public void select_left_window() {
            select_horizontal_terminal(true);
            
            update_focus_terminal(get_focus_term(this));
        }
        
        public void select_right_window() {
            select_horizontal_terminal(false);
            
            update_focus_terminal(get_focus_term(this));
        }
        
        public void select_up_window() {
            select_vertical_terminal(true);
            
            update_focus_terminal(get_focus_term(this));
        }
        
        public void select_down_window() {
            select_vertical_terminal(false);
            
            update_focus_terminal(get_focus_term(this));
        }
        
        public ArrayList<Term> find_intersects_horizontal_terminals(Gtk.Allocation rect, bool left=true) {
            ArrayList<Term> intersects_terminals = new ArrayList<Term>();
            foreach (Term t in term_list) {
                Gtk.Allocation alloc = Utils.get_origin_allocation(t);
                
                if (alloc.y < rect.y + rect.height + PANED_HANDLE_SIZE && alloc.y + alloc.height + PANED_HANDLE_SIZE > rect.y) {
                    if (left) {
                        if (alloc.x + alloc.width + PANED_HANDLE_SIZE == rect.x) {
                            intersects_terminals.add(t);
                        }
                    } else {
                        if (alloc.x == rect.x + rect.width + PANED_HANDLE_SIZE) {
                            intersects_terminals.add(t);
                        }
                    }
                }
            }
            
            return intersects_terminals;
        }
        
        public void select_horizontal_terminal(bool left=true) {
            Term focus_term = get_focus_term(this);
            
            Gtk.Allocation rect = Utils.get_origin_allocation(focus_term);
            int y = rect.y;
            int h = rect.height;

            ArrayList<Term> intersects_terminals = find_intersects_horizontal_terminals(rect, left);
            if (intersects_terminals.size > 0) {
                ArrayList<Term> same_coordinate_terminals = new ArrayList<Term>();
                foreach (Term t in intersects_terminals) {
                    Gtk.Allocation alloc = Utils.get_origin_allocation(t);
                    
                    if (alloc.y == y) {
                        same_coordinate_terminals.add(t);
                    }
                }
                
                if (same_coordinate_terminals.size > 0) {
                    same_coordinate_terminals[0].focus_term();
                } else {
                    ArrayList<Term> bigger_match_terminals = new ArrayList<Term>();
                    foreach (Term t in intersects_terminals) {
                        Gtk.Allocation alloc = Utils.get_origin_allocation(t);;
                        
                        if (alloc.y < y && alloc.y + alloc.height >= y + h) {
                            bigger_match_terminals.add(t);
                        }
                    }
                    
                    if (bigger_match_terminals.size > 0) {
                        bigger_match_terminals[0].focus_term();
                    } else {
                        Term biggest_intersectant_terminal = null;
                        int area = 0;
                        foreach (Term t in intersects_terminals) {
                            Gtk.Allocation alloc = Utils.get_origin_allocation(t);;
                            
                            int term_area = alloc.height + h - (alloc.y - y).abs() - (alloc.y + alloc.height - y - h).abs() / 2;
                            if (term_area > area) {
                                biggest_intersectant_terminal = t;
                            }
                        }
                        
                        if (biggest_intersectant_terminal != null) {
                            biggest_intersectant_terminal.focus_term();
                        }
                    }
                }
            }
        }
        
        public ArrayList<Term> find_intersects_vertical_terminals(Gtk.Allocation rect, bool up=true) {
            ArrayList<Term> intersects_terminals = new ArrayList<Term>();
            foreach (Term t in term_list) {
                Gtk.Allocation alloc = Utils.get_origin_allocation(t);
                
                if (alloc.x < rect.x + rect.width + PANED_HANDLE_SIZE && alloc.x + alloc.width + PANED_HANDLE_SIZE > rect.x) {
                    if (up) {
                        if (alloc.y + alloc.height + PANED_HANDLE_SIZE == rect.y) {
                            intersects_terminals.add(t);
                        }
                    } else {
                        if (alloc.y == rect.y + rect.height + PANED_HANDLE_SIZE) {
                            intersects_terminals.add(t);
                        }
                    }
                }
            }
            
            return intersects_terminals;
        }
        
        public void select_vertical_terminal(bool up=true) {
            Term focus_term = get_focus_term(this);
            
            Gtk.Allocation rect = Utils.get_origin_allocation(focus_term);
            int x = rect.x;
            int w = rect.width;

            ArrayList<Term> intersects_terminals = find_intersects_vertical_terminals(rect, up);
            if (intersects_terminals.size > 0) {
                ArrayList<Term> same_coordinate_terminals = new ArrayList<Term>();
                foreach (Term t in intersects_terminals) {
                    Gtk.Allocation alloc = Utils.get_origin_allocation(t);
                    
                    if (alloc.x == x) {
                        same_coordinate_terminals.add(t);
                    }
                }
                
                if (same_coordinate_terminals.size > 0) {
                    same_coordinate_terminals[0].focus_term();
                } else {
                    ArrayList<Term> bigger_match_terminals = new ArrayList<Term>();
                    foreach (Term t in intersects_terminals) {
                        Gtk.Allocation alloc = Utils.get_origin_allocation(t);;
                        
                        if (alloc.x < x && alloc.x + alloc.width >= x + w) {
                            bigger_match_terminals.add(t);
                        }
                    }
                    
                    if (bigger_match_terminals.size > 0) {
                        bigger_match_terminals[0].focus_term();
                    } else {
                        Term biggest_intersectant_terminal = null;
                        int area = 0;
                        foreach (Term t in intersects_terminals) {
                            Gtk.Allocation alloc = Utils.get_origin_allocation(t);;
                            
                            int term_area = alloc.width + w - (alloc.x - x).abs() - (alloc.x + alloc.width - x - w).abs() / 2;
                            if (term_area > area) {
                                biggest_intersectant_terminal = t;
                            }
                        }
                        
                        if (biggest_intersectant_terminal != null) {
                            biggest_intersectant_terminal.focus_term();
                        }
                    }
                }
            }
        }
        
        public void search() {
            remove_remote_panel();
            remove_theme_panel();
            
            terminal_before_popup = get_focus_term(this);
            if (search_panel == null && terminal_before_popup != null) {
                
                search_panel = new SearchPanel(((Widgets.ConfigWindow) get_toplevel()), terminal_before_popup);
                search_panel.quit_search.connect((w) => {
                        remove_search_panel();
                    });
                add_overlay(search_panel);
                show_all();            
            }
            
            search_panel.search_entry.grab_focus();
        }
        
        public void remove_search_panel() {
            if (search_panel != null) {
                remove(search_panel);
                search_panel.destroy();
                search_panel = null;
            }
            
            if (terminal_before_popup != null) {
                terminal_before_popup.focus_term();
                terminal_before_popup.term.unselect_all();
                terminal_before_popup = null;
            }
        }
        
		public void toggle_remote_panel(Workspace workspace) {
			if (remote_panel == null) {
				show_remote_panel(workspace);
			} else {
				hide_remote_panel();
			}
		}
		
		public void show_remote_panel(Workspace workspace) {
            remove_search_panel();
            remove_theme_panel();
            
			if (remote_panel == null) {
				Gtk.Allocation rect;
				get_allocation(out rect);
				
				remote_panel = new RemotePanel(workspace, workspace_manager);
				remote_panel.set_size_request(Constant.SLIDER_WIDTH, rect.height);
                add_overlay(remote_panel);
				
				show_all();
                
                remote_panel.margin_left = rect.width;
                show_slider_start_x = rect.width;
                remote_panel_show_timer.reset();
			}
            
            terminal_before_popup = get_focus_term(this);
		}
		
		public void hide_remote_panel() {
			if (remote_panel != null) {
				Gtk.Allocation rect;
				get_allocation(out rect);
                
                hide_slider_start_x = rect.width - Constant.SLIDER_WIDTH;
                remote_panel_hide_timer.reset();
			}
		}
        
        public void remove_remote_panel() {
            if (remote_panel != null) {
                remove(remote_panel);
                remote_panel.destroy();
                remote_panel = null;
            }
            
            if (terminal_before_popup != null) {
                terminal_before_popup.focus_term();
                terminal_before_popup = null;
            }
        }
        
		public void remote_panel_show_animate(double progress) {
            remote_panel.margin_left = (int) (show_slider_start_x - Constant.SLIDER_WIDTH * progress);
            
            if (progress >= 1.0) {
				remote_panel_show_timer.stop();
			}
		}

		public void remote_panel_hide_animate(double progress) {
            remote_panel.margin_left = (int) (hide_slider_start_x + Constant.SLIDER_WIDTH * progress);
            
            if (progress >= 1.0) {
				remote_panel_hide_timer.stop();

                remove_remote_panel();
			}
		}

		public void toggle_theme_panel(Workspace workspace) {
			if (theme_panel == null) {
				show_theme_panel(workspace);
			} else {
				hide_theme_panel();
			}
		}
		
		public void show_theme_panel(Workspace workspace) {
            remove_search_panel();
            remove_remote_panel();
            
			if (theme_panel == null) {
				Gtk.Allocation rect;
				get_allocation(out rect);
				
				theme_panel = new ThemePanel(workspace, workspace_manager);
				theme_panel.set_size_request(Constant.THEME_SLIDER_WIDTH, rect.height);
                add_overlay(theme_panel);
				
				show_all();
                
                theme_panel.margin_left = rect.width;
                show_slider_start_x = rect.width;
                theme_panel_show_timer.reset();
			}
            
            terminal_before_popup = get_focus_term(this);
		}
		
		public void hide_theme_panel() {
			if (theme_panel != null) {
				Gtk.Allocation rect;
				get_allocation(out rect);
                
                hide_slider_start_x = rect.width - Constant.THEME_SLIDER_WIDTH;
                theme_panel_hide_timer.reset();
			}
		}
        
        public void remove_theme_panel() {
            if (theme_panel != null) {
                remove(theme_panel);
                theme_panel.destroy();
                theme_panel = null;
            }
            
            if (terminal_before_popup != null) {
                terminal_before_popup.focus_term();
                terminal_before_popup = null;
            }
        }
        
		public void theme_panel_show_animate(double progress) {
            theme_panel.margin_left = (int) (show_slider_start_x - Constant.THEME_SLIDER_WIDTH * progress);
            
            if (progress >= 1.0) {
				theme_panel_show_timer.stop();
			}
		}

		public void theme_panel_hide_animate(double progress) {
            theme_panel.margin_left = (int) (hide_slider_start_x + Constant.THEME_SLIDER_WIDTH * progress);
            
            if (progress >= 1.0) {
				theme_panel_hide_timer.stop();

                remove_theme_panel();
			}
		}
        
        public void remove_all_panel() {
            remove_search_panel();
            remove_remote_panel();
            remove_theme_panel();
        }
        
        public void update_focus_terminal(Term term) {
            focus_terminal = term;
        }
        
        public void select_focus_terminal() {
            if (focus_terminal != null) {
                focus_terminal.focus_term();
            }
        }
    }
}